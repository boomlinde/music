Various JACK music tools and experiments implemented in Zig

Includes a MIDI stream parser (midi.zig) an SMF parser (SMF.zig) and an
SMF player library (SMFStreamer.zig).

# Synths

## pdsynth

A simple phase distortion synthesizer with an SDL GUI.

## drummer

Drum synth based on FM with filtered noise as a modulator

## karplus

Karplus-Strong feeback delay synthesizer

## jack-mt32

No-nonense JACK wrapper for munt mt32emu. Currently expects ctrl\_mt32.rom
and pcm\_mt32.rom in cwd.

# Tools

## autoconnect

Listens for new JACK ports and automatically connects them according to a
rule file with rules in the following format:

    from "source1:port" to "destination1:port"
    from "source2:port" to "destination2:port"

* It accepts wildcards (`*` and `?`) in the port names.
* It reloads the rule list every time something is connected, so you can
  change the rules without restarting it.

## smfplay

An SMF player. Starts playing the given file once connected to a MIDI sink.

Options:

* `--gm`: Perform GM Start reset SysEx before playback
* `--gs`: Perform GS reset before playback
* `--mt`: Perform MT reset before playback
* `--noresetcc`: Don't reset controllers before playback

## jack-activesensing

Simply generate a steady stream of MIDI active sensing messages.

## midivis

Visualizes all the incoming MIDI notes on one keyboard display for each
channel.
