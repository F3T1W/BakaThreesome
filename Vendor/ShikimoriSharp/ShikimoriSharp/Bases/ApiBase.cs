using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using ShikimoriSharp.Exceptions;

namespace ShikimoriSharp.Bases
{
    public abstract class ApiBase
    {
        private readonly ApiClient _apiClient;

        protected ApiBase(Version version, ApiClient apiClient)
        {
            Version = version;
            _apiClient = apiClient;
        }

        public Version Version { get; }
        private string Site => $"https://shikimori.io/api/{GetThing()}";

        protected bool Requires(AccessToken token, IEnumerable<string> scopes)
        {
            var scope = (token?.Scope ?? "").Split(" ");
            if (!scopes.All(it => scope.Any(x => x == it)))
                throw new NotInScopeException();
            return true;
        }

        private string GetThing()
        {
            return Version switch
            {
                Version.v1 => "",
                _ => Version + "/"
            };
        }

        private static HttpContent DeserializeToRequest<T>(T obj)
        {
            if (obj is null) return null;
            var fields = new List<KeyValuePair<string, string>>();
            foreach (var field in obj.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                var value = field.GetValue(obj);
                if (value is null) continue;
                var text = value is bool boolean ? (boolean ? "true" : "false")
                    : value is Array array ? string.Join(",", array.Cast<object>())
                    : Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture);
                fields.Add(new KeyValuePair<string, string>(field.Name, text));
            }
            return new FormUrlEncodedContent(fields);
        }

        public async Task<TResult> Request<TResult, TSettings>(string apiMethod, TSettings settings,
            AccessToken token = null, string method = "GET")
        {
            using var content = DeserializeToRequest(settings);
            var destination = $"{Site}{apiMethod}";
            if (method == "GET" && content != null)
            {
                destination += "?" + await content.ReadAsStringAsync();
                return await _apiClient.RequestForm<TResult>(destination, token, method);
            }
            return await _apiClient.RequestForm<TResult>(destination, content, token, method);
        }

        private static async Task<string> SerializeToJson(object obj)
        {
            return await Task.Factory.StartNew(() => JsonConvert.SerializeObject(obj, new JsonSerializerSettings { NullValueHandling = NullValueHandling.Ignore, Converters = { new Newtonsoft.Json.Converters.StringEnumConverter() } }));
        }

        public async Task<TResult> SendJson<TResult>(string apiMethod, object content, AccessToken token,
            string method = "POST")
        {
            var json = new StringContent(await SerializeToJson(content), Encoding.UTF8, "application/json");
            return await _apiClient.RequestForm<TResult>($"{Site}{apiMethod}", json, token, method);
        }

        public async Task<TResult> Request<TResult>(string apiMethod, AccessToken token = null, string method = "GET")
        {
            return await _apiClient.RequestForm<TResult>($"{Site}{apiMethod}", token, method);
        }

        public async Task NoResponseRequest(string apiMethod, AccessToken token, string method = "POST")
        {
            await _apiClient.RequestWithNoResponse($"{Site}{apiMethod}", null, token, method);
        }

        public async Task NoResponseRequest<TSettings>(string apiMethod, TSettings setting, AccessToken token,
            string method = "POST")
        {
            var settings = DeserializeToRequest(setting);
            await _apiClient.RequestWithNoResponse($"{Site}{apiMethod}", settings, token, method);
        }
    }

    public enum Version
    {
        v1,
        v2
    }
}