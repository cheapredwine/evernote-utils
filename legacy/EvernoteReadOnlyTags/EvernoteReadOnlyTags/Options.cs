using System;

using CommandLine;
using CommandLine.Parsing;

namespace EvernoteReadOnlyTags
{
    class Options
    {
        [Option('i', "interactive", DefaultValue = false, HelpText = "App should run in interactive mode. Use this to unset ReadOnly.")]
        public bool Interactive { get; set; }

        [ParserState]
        public IParserState LastParserState { get; set; }

        [HelpOption]
        public string GetUsage()
        {
            return "EvernoteReadOnlyTags.exe [-i] [-s]" + Environment.NewLine;
        }
                
        [Option('s', "createSampleReadOnlyNote", DefaultValue = false, HelpText = "Create a sample note set to readonly.")]
        public bool CreateSampleReadOnlyNote { get; set; }
    }
}