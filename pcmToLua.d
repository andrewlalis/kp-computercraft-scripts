#!/usr/bin/env rdmd
/**
 * Converts a signed 8-bit PCM audio file into a Lua table list. Run this from
 * the command-line via `./pcmToLua my-pcm-file.pcm`.
 */
module pcm_to_lua;

import std.stdio;
import std.file;
import std.array;

const frameSize = 128 * 1024;

int main(string[] args) {
    if (args.length < 2) {
        stderr.writeln("Missing required file.");
        return 1;
    }
    string audioFilename = args[1];
    if (!exists(audioFilename)) {
        stderr.writefln!"File %s doesn't exist."(audioFilename);
        return 1;
    }

    byte[] contents = cast(byte[]) std.file.read(audioFilename);
    ulong sampleIndex = 0;
    auto app = appender!string;
    stdout.writeln("local audio = {");
    foreach (byte sample; contents) {
        stdout.writefln!"    %d,"(sample);
        sampleIndex++;
    }
    stdout.writeln("}");

    return 0;
}

