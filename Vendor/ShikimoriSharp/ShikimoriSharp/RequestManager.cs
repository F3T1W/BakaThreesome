using System;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using ShikimoriSharp.Bases;

namespace ShikimoriSharp
{
    public sealed class ShikimoriRequestException : Exception
    {
        public HttpStatusCode StatusCode { get; }
        public ShikimoriRequestException(HttpStatusCode statusCode)
            : base("The Shikimori request was rejected.") { StatusCode = statusCode; }
    }

    public class RequestManager
    {
        private readonly TokenBucket _bucketRpm;
        private readonly TokenBucket _bucketRps;
        private readonly ClientSettings _settings;
        private readonly AccessToken _token;
        private readonly HttpClient _client;

        public RequestManager(ILogger logger, TokenBucket bucketRps, TokenBucket bucketRpm,
            ClientSettings settings, AccessToken token, Func<AccessToken, Task<AccessToken>> refresh,
            HttpClient client = null)
        {
            _bucketRpm = bucketRpm;
            _bucketRps = bucketRps;
            _settings = settings;
            _token = token;
            _client = client ?? new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
                { Timeout = TimeSpan.FromSeconds(15) };
        }

        public async Task<string> ResponseExecutor(string destination, string method, HttpContent content)
        {
            await _bucketRpm.TokenRequest();
            await _bucketRps.TokenRequest();
            using var request = new HttpRequestMessage(new HttpMethod(method), destination);
            request.Headers.TryAddWithoutValidation("User-Agent", _settings.ClientName);
            if (_token != null)
                request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {_token.Access_Token}");
            request.Content = content;
            // Account code owns token rotation. Never refresh or repeat a write implicitly.
            using var response = await _client.SendAsync(request);
            if (!response.IsSuccessStatusCode)
                throw new ShikimoriRequestException(response.StatusCode);
            return await response.Content.ReadAsStringAsync();
        }

        public async Task<TResult> ResponseAsType<TResult>(string destination, string method, HttpContent content)
        {
            return JsonConvert.DeserializeObject<TResult>(await ResponseExecutor(destination, method, content));
        }
    }
}
