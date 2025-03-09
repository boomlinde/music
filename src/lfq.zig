pub fn LockFreeQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        head: usize = 0,
        tail: usize = 0,
        buffer: [capacity]T = undefined,

        pub fn enqueue(self: *Self, item: T) !void {
            const tail = @atomicLoad(usize, &self.tail, .monotonic);
            const head = @atomicLoad(usize, &self.head, .acquire);

            const next_tail = (tail + 1) % capacity;

            if (next_tail == head) return error.Full;

            self.buffer[tail] = item;

            @atomicStore(usize, &self.tail, next_tail, .release);
        }

        pub fn dequeue(self: *Self) ?T {
            const head = @atomicLoad(usize, &self.head, .monotonic);
            const tail = @atomicLoad(usize, &self.tail, .acquire);

            if (head == tail) return null;

            const next_head = (head + 1) % capacity;
            const item = self.buffer[head];

            @atomicStore(usize, &self.head, next_head, .release);

            return item;
        }
    };
}

test LockFreeQueue {
    const t = @import("std").testing;

    var q = LockFreeQueue(usize, 3){};

    try q.enqueue(1);
    try q.enqueue(2);
    try t.expectError(error.Full, q.enqueue(3));
    try t.expectEqual(1, q.dequeue());
    try q.enqueue(3);
    try t.expectEqual(2, q.dequeue());
    try t.expectEqual(3, q.dequeue());
    try t.expectEqual(null, q.dequeue());
}
