using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace ShikimoriSharp.Bases
{
    public class TokenBucket
    {
        private readonly SemaphoreSlim _gate = new SemaphoreSlim(1, 1);
        private readonly Queue<long> _requests = new Queue<long>();
        public string Name { get; }
        public int MaxTokens { get; }
        public double RefreshTime { get; }

        public TokenBucket(string name, int maxTokens, double refreshTime)
        {
            Name = name;
            MaxTokens = maxTokens;
            RefreshTime = refreshTime;
        }

        public async Task TokenRequest()
        {
            while (true)
            {
                double delay;
                await _gate.WaitAsync();
                try
                {
                    var now = Stopwatch.GetTimestamp();
                    while (_requests.Count > 0 && Milliseconds(now - _requests.Peek()) >= RefreshTime)
                        _requests.Dequeue();
                    if (_requests.Count < MaxTokens)
                    {
                        _requests.Enqueue(now);
                        return;
                    }
                    delay = RefreshTime - Milliseconds(now - _requests.Peek());
                }
                finally { _gate.Release(); }
                await Task.Delay(TimeSpan.FromMilliseconds(Math.Max(1, delay)));
            }
        }

        private static double Milliseconds(long ticks) => ticks * 1000d / Stopwatch.Frequency;
    }
}
