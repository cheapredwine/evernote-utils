using System;

namespace EvernoteReadOnlyTags
{
    class EvernoteReadOnlyTagsException : Exception
    {

        public EvernoteReadOnlyTagsException(string message) : base(message)
        {
        }
        public EvernoteReadOnlyTagsException()
        {
        }

        public static void Assert(bool condition)
        {
            if (!condition)
            {
                throw new EvernoteReadOnlyTagsException();
            }
        }

        public static void Assert(bool condition, string message)
        {
            if (!condition)
            {
                throw new EvernoteReadOnlyTagsException(message);
            }
        }
    }
}
