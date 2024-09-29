const List = @import("list.zig").List;

pub fn RoundRobinManager(
    comptime Voice: type,
    comptime n: usize,
) type {
    return struct {
        pub const Gen = struct {
            voice: Voice,
            generation: usize = 0,

            fn link(self: *Gen) *List(Gen).Link {
                return @fieldParentPtr("value", self);
            }
        };
        const Ref = struct {
            generation: usize,
            wrapper: *Gen,

            inline fn valid(self: Ref) bool {
                return self.generation == self.wrapper.generation;
            }

            inline fn get(self: Ref) ?*Gen {
                return if (self.valid()) self.wrapper else null;
            }
        };

        links: [n]List(Gen).Link,

        used: List(Gen) = .{},
        free: List(Gen) = .{},
        keys: [128]?Ref = [_]?Ref{null} ** 128,

        pub fn reset(self: *@This()) void {
            self.used.clear();
            self.free.clear();
            for (&self.links) |*link| self.free.pushBack(link);
        }

        pub fn noteOn(self: *@This(), pitch: u7, velocity: u7) void {
            // According to MIDI, a note-on with a velocity of 0
            // represents releasing the key, so we'lll deal with this
            // as a note-off with medium velocity.
            if (velocity == 0) return self.noteOff(pitch, 64);
            if (self.isPlaying(pitch)) return;

            const ref = self.allocateVoice();
            self.keys[pitch] = ref;
            ref.wrapper.voice.noteOn(pitch, velocity);
        }

        pub fn noteOff(self: *@This(), pitch: u7, velocity: u7) void {
            defer self.keys[pitch] = null;

            if (self.keys[pitch]) |ref| if (ref.get()) |wrapper| {
                wrapper.voice.noteOff(velocity);
                self.used.unlink(wrapper.link());
                self.free.pushBack(wrapper.link());
            };
        }

        pub fn pitchWheel(self: *@This(), value: u14) void {
            for (&self.links) |*l| l.value.voice.pitchWheel(value);
        }

        pub inline fn next(self: *@This(), params: *const Voice.Params, srate: f32) f32 {
            var sum: f32 = 0;
            for (&self.links) |*l| sum += l.value.voice.next(params, srate);
            return sum;
        }

        inline fn isPlaying(self: *@This(), pitch: u7) bool {
            if (self.keys[pitch]) |ref| return ref.valid();
            return false;
        }

        inline fn allocateVoice(self: *@This()) Ref {
            if (self.free.popFront()) |v| {
                v.value.generation +%= 1;
                self.used.pushBack(v);
                return .{
                    .generation = v.value.generation,
                    .wrapper = &v.value,
                };
            }

            if (self.used.popFront()) |v| {
                v.value.generation +%= 1;
                self.used.pushBack(v);
                return .{
                    .generation = v.value.generation,
                    .wrapper = &v.value,
                };
            }

            unreachable;
        }
    };
}
