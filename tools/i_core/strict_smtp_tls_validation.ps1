$ErrorActionPreference = 'Stop'

function Initialize-StrictSmtpTlsValidation {
  if ('HereIam.ICore.Security.StrictSmtpTlsValidation' -as [type]) { return }

  Add-Type -AssemblyName System.Net.Http
  Add-Type -ReferencedAssemblies @('System.Net.Http.dll') -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Security;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

namespace HereIam.ICore.Security
{
    public static class StrictSmtpTlsValidation
    {
        private const int MaxCrlUrls = 8;
        private const int MaxCrlBytes = 4 * 1024 * 1024;
        private const int MaxTotalCrlBytes = 12 * 1024 * 1024;
        private const int MaxAsnDepth = 16;
        private const int MaxAsnNodes = 1024;

        private const uint X509_ASN_ENCODING = 0x00000001;
        private const uint PKCS_7_ASN_ENCODING = 0x00010000;
        private const uint CERT_STORE_CREATE_NEW_FLAG = 0x00002000;
        private const uint CERT_STORE_ADD_ALWAYS = 4;
        private const uint CERT_CHAIN_DISABLE_AUTH_ROOT_AUTO_UPDATE = 0x00000100;
        private const uint CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL = 0x00000004;
        private const uint CERT_CHAIN_DISABLE_AIA = 0x00002000;
        private const uint CERT_CHAIN_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT = 0x40000000;
        private const uint CERT_CHAIN_REVOCATION_CHECK_CACHE_ONLY = 0x80000000;
        private const uint AUTHTYPE_SERVER = 2;

        private static readonly IntPtr CertStoreProvMemory = new IntPtr(2);
        private static readonly IntPtr CertChainPolicySsl = new IntPtr(4);

        public static RemoteCertificateValidationCallback CreateCallback(string serverName, int downloadBudgetMs)
        {
            if (!String.Equals(serverName, "smtp.gmail.com", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("TLS server name is not allowed.");
            if (downloadBudgetMs < 1000 || downloadBudgetMs > 12000)
                throw new InvalidOperationException("TLS CRL budget is invalid.");

            return delegate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors)
            {
                try
                {
                    return ValidatePeer(serverName, downloadBudgetMs, certificate, chain, errors);
                }
                catch
                {
                    return false;
                }
            };
        }

        public static bool IsAllowedCrlUri(string value)
        {
            Uri uri;
            if (String.IsNullOrWhiteSpace(value) ||
                !Uri.TryCreate(value, UriKind.Absolute, out uri))
                return false;
            if (!String.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
                return false;
            if (!String.IsNullOrEmpty(uri.UserInfo) || !String.IsNullOrEmpty(uri.Fragment) ||
                !uri.IsDefaultPort || uri.HostNameType != UriHostNameType.Dns)
                return false;

            string host = uri.DnsSafeHost;
            return String.Equals(host, "pki.goog", StringComparison.OrdinalIgnoreCase) ||
                   String.Equals(host, "c.pki.goog", StringComparison.OrdinalIgnoreCase) ||
                   String.Equals(host, "crl.pki.goog", StringComparison.OrdinalIgnoreCase);
        }

        public static byte[] DownloadForTest(HttpMessageHandler handler, string value, int budgetMs, int maxBodyBytes)
        {
            if (handler == null || !IsAllowedCrlUri(value) || budgetMs < 1 || maxBodyBytes < 1)
                throw new InvalidOperationException("Test download input is invalid.");
            int totalBytes = 0;
            Stopwatch stopwatch = Stopwatch.StartNew();
            try
            {
                return DownloadOne(handler, new Uri(value), stopwatch, budgetMs, maxBodyBytes, maxBodyBytes, ref totalBytes);
            }
            finally
            {
                handler.Dispose();
            }
        }

        public static bool InvokeFailClosedCallbackForTest(SslPolicyErrors errors)
        {
            RemoteCertificateValidationCallback callback = CreateCallback("smtp.gmail.com", 1000);
            return callback(null, null, null, errors);
        }

        private static bool ValidatePeer(
            string serverName,
            int downloadBudgetMs,
            X509Certificate certificate,
            X509Chain chain,
            SslPolicyErrors errors)
        {
            if (certificate == null || chain == null || errors != SslPolicyErrors.None)
                return false;
            if (chain.ChainElements == null || chain.ChainElements.Count < 2)
                return false;

            X509Certificate2 leaf = certificate as X509Certificate2;
            bool disposeLeaf = false;
            if (leaf == null)
            {
                leaf = new X509Certificate2(certificate);
                disposeLeaf = true;
            }

            try
            {
                if (!BytesEqual(leaf.RawData, chain.ChainElements[0].Certificate.RawData))
                    return false;
                for (int i = 0; i < chain.ChainStatus.Length; i++)
                    if (chain.ChainStatus[i].Status != X509ChainStatusFlags.NoError)
                        return false;

                List<Uri> crlUris = ExtractRequiredCrlUris(chain);
                List<byte[]> crls = DownloadCrls(crlUris, downloadBudgetMs);
                try
                {
                    return ValidateWithCrypt32(serverName, leaf, chain, crls);
                }
                finally
                {
                    for (int i = 0; i < crls.Count; i++)
                        Array.Clear(crls[i], 0, crls[i].Length);
                }
            }
            finally
            {
                if (disposeLeaf) leaf.Dispose();
            }
        }

        private static List<Uri> ExtractRequiredCrlUris(X509Chain chain)
        {
            List<Uri> result = new List<Uri>();
            HashSet<string> unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int nonRootCount = chain.ChainElements.Count - 1;

            for (int elementIndex = 0; elementIndex < nonRootCount; elementIndex++)
            {
                X509Certificate2 certificate = chain.ChainElements[elementIndex].Certificate;
                List<string> certificateUris = new List<string>();
                int matchingExtensions = 0;
                foreach (X509Extension extension in certificate.Extensions)
                {
                    if (extension.Oid != null && extension.Oid.Value == "2.5.29.31")
                    {
                        matchingExtensions++;
                        int nodes = 0;
                        ParseCdpExtension(extension.RawData, ref nodes, certificateUris);
                    }
                }

                if (matchingExtensions != 1 || certificateUris.Count == 0)
                    throw new InvalidOperationException("Certificate CRL distribution points are unavailable.");

                if (certificateUris.Count > MaxCrlUrls)
                    throw new InvalidOperationException("Certificate CRL distribution point limit exceeded.");
                for (int uriIndex = 0; uriIndex < certificateUris.Count; uriIndex++)
                {
                    string value = certificateUris[uriIndex];
                    if (!IsAllowedCrlUri(value))
                        throw new InvalidOperationException("Certificate CRL distribution point is not allowed.");
                    Uri uri = new Uri(value, UriKind.Absolute);
                    if (unique.Add(uri.AbsoluteUri))
                    {
                        if (result.Count >= MaxCrlUrls)
                            throw new InvalidOperationException("Certificate CRL distribution point limit exceeded.");
                        result.Add(uri);
                    }
                }
            }

            if (result.Count == 0)
                throw new InvalidOperationException("Certificate CRL distribution points are unavailable.");
            return result;
        }

        private static void ParseCdpExtension(byte[] encoded, ref int nodes, List<string> uris)
        {
            if (encoded == null || encoded.Length < 2 || encoded[0] != 0x30)
                throw new InvalidOperationException("Certificate CRL distribution points are malformed.");
            int cursor = 1;
            int length = ReadDerLength(encoded, ref cursor, encoded.Length);
            if (length < 1 || cursor != encoded.Length - length)
                throw new InvalidOperationException("Certificate CRL distribution points are malformed.");
            ParseCdp(encoded, cursor, encoded.Length, 1, ref nodes, uris);
        }

        private static void ParseCdp(
            byte[] encoded,
            int offset,
            int end,
            int depth,
            ref int nodes,
            List<string> uris)
        {
            if (encoded == null || offset < 0 || end < offset || end > encoded.Length || depth > MaxAsnDepth)
                throw new InvalidOperationException("Certificate CRL distribution points are malformed.");

            int cursor = offset;
            while (cursor < end)
            {
                if (++nodes > MaxAsnNodes || cursor >= end)
                    throw new InvalidOperationException("Certificate CRL distribution points are malformed.");

                byte tag = encoded[cursor++];
                if ((tag & 0x1f) == 0x1f)
                    throw new InvalidOperationException("Certificate CRL distribution points are malformed.");
                int length = ReadDerLength(encoded, ref cursor, end);
                if (length < 0 || cursor > end - length)
                    throw new InvalidOperationException("Certificate CRL distribution points are malformed.");
                int valueEnd = cursor + length;

                if (tag == 0x86)
                {
                    if (length < 1 || length > 2048)
                        throw new InvalidOperationException("Certificate CRL distribution point is malformed.");
                    for (int i = cursor; i < valueEnd; i++)
                        if (encoded[i] < 0x21 || encoded[i] > 0x7e)
                            throw new InvalidOperationException("Certificate CRL distribution point is malformed.");
                    uris.Add(Encoding.ASCII.GetString(encoded, cursor, length));
                }
                else if ((tag & 0x20) != 0)
                {
                    ParseCdp(encoded, cursor, valueEnd, depth + 1, ref nodes, uris);
                }

                cursor = valueEnd;
            }

            if (cursor != end)
                throw new InvalidOperationException("Certificate CRL distribution points are malformed.");
        }

        private static int ReadDerLength(byte[] encoded, ref int cursor, int end)
        {
            if (cursor >= end) throw new InvalidOperationException("DER length is missing.");
            int first = encoded[cursor++];
            if ((first & 0x80) == 0) return first;

            int count = first & 0x7f;
            if (count < 1 || count > 4 || cursor > end - count || encoded[cursor] == 0)
                throw new InvalidOperationException("DER length is invalid.");
            int length = 0;
            for (int i = 0; i < count; i++)
            {
                if (length > (Int32.MaxValue >> 8))
                    throw new InvalidOperationException("DER length is invalid.");
                length = (length << 8) | encoded[cursor++];
            }
            if (length < 128) throw new InvalidOperationException("DER length is not minimal.");
            return length;
        }

        private static List<byte[]> DownloadCrls(List<Uri> uris, int budgetMs)
        {
            HttpClientHandler handler = new HttpClientHandler();
            handler.UseProxy = false;
            handler.AllowAutoRedirect = false;
            handler.AutomaticDecompression = DecompressionMethods.None;

            List<byte[]> result = new List<byte[]>();
            Stopwatch stopwatch = Stopwatch.StartNew();
            int totalBytes = 0;
            try
            {
                for (int i = 0; i < uris.Count; i++)
                    result.Add(DownloadOne(handler, uris[i], stopwatch, budgetMs, MaxCrlBytes, MaxTotalCrlBytes, ref totalBytes));
                return result;
            }
            catch
            {
                for (int i = 0; i < result.Count; i++)
                    Array.Clear(result[i], 0, result[i].Length);
                throw;
            }
            finally
            {
                handler.Dispose();
            }
        }

        private static byte[] DownloadOne(
            HttpMessageHandler handler,
            Uri uri,
            Stopwatch stopwatch,
            int budgetMs,
            int maxBodyBytes,
            int maxTotalBytes,
            ref int totalBytes)
        {
            int remainingMs = budgetMs - checked((int)stopwatch.ElapsedMilliseconds);
            if (remainingMs <= 0) throw new TimeoutException("CRL download budget exceeded.");

            using (HttpClient client = new HttpClient(handler, false))
            using (CancellationTokenSource requestTimeout = new CancellationTokenSource(remainingMs))
            {
                client.Timeout = TimeSpan.FromMilliseconds(remainingMs);
                using (HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Get, uri))
                using (HttpResponseMessage response = client.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    requestTimeout.Token).GetAwaiter().GetResult())
                {
                    if (response.StatusCode != HttpStatusCode.OK)
                        throw new InvalidOperationException("CRL download did not return a complete response.");
                    if (response.Content == null)
                        throw new InvalidOperationException("CRL download returned no body.");

                    long? declaredLength = response.Content.Headers.ContentLength;
                    if (declaredLength.HasValue &&
                        (declaredLength.Value < 1 || declaredLength.Value > maxBodyBytes ||
                         declaredLength.Value > maxTotalBytes - totalBytes))
                        throw new InvalidOperationException("CRL download body is oversized.");

                    using (Stream stream = response.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
                    using (MemoryStream body = new MemoryStream())
                    {
                        byte[] buffer = new byte[8192];
                        try
                        {
                            while (true)
                            {
                                if (stopwatch.ElapsedMilliseconds >= budgetMs)
                                    throw new TimeoutException("CRL download budget exceeded.");
                                int read = stream.ReadAsync(
                                    buffer,
                                    0,
                                    buffer.Length,
                                    requestTimeout.Token).GetAwaiter().GetResult();
                                if (read == 0) break;
                                if (body.Length + read > maxBodyBytes || totalBytes + body.Length + read > maxTotalBytes)
                                    throw new InvalidOperationException("CRL download body is oversized.");
                                body.Write(buffer, 0, read);
                            }
                            if (body.Length == 0)
                                throw new InvalidOperationException("CRL download returned an empty body.");
                            if (declaredLength.HasValue && body.Length != declaredLength.Value)
                                throw new InvalidOperationException("CRL download body is incomplete.");
                            byte[] bytes = body.ToArray();
                            totalBytes = checked(totalBytes + bytes.Length);
                            return bytes;
                        }
                        finally
                        {
                            Array.Clear(buffer, 0, buffer.Length);
                        }
                    }
                }
            }
        }

        private static bool ValidateWithCrypt32(
            string serverName,
            X509Certificate2 leaf,
            X509Chain suppliedChain,
            List<byte[]> crls)
        {
            IntPtr memoryStore = IntPtr.Zero;
            IntPtr chainEngine = IntPtr.Zero;
            IntPtr chainContext = IntPtr.Zero;
            IntPtr additionalStores = IntPtr.Zero;
            IntPtr serverNamePointer = IntPtr.Zero;
            List<IntPtr> crlContexts = new List<IntPtr>();

            try
            {
                memoryStore = NativeMethods.CertOpenStore(
                    CertStoreProvMemory,
                    X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
                    IntPtr.Zero,
                    CERT_STORE_CREATE_NEW_FLAG,
                    IntPtr.Zero);
                if (memoryStore == IntPtr.Zero) return false;

                for (int i = 1; i < suppliedChain.ChainElements.Count - 1; i++)
                {
                    if (!NativeMethods.CertAddCertificateContextToStore(
                        memoryStore,
                        suppliedChain.ChainElements[i].Certificate.Handle,
                        CERT_STORE_ADD_ALWAYS,
                        IntPtr.Zero))
                        return false;
                }

                for (int i = 0; i < crls.Count; i++)
                {
                    IntPtr crlContext;
                    if (!NativeMethods.CertAddEncodedCRLToStore(
                        memoryStore,
                        X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
                        crls[i],
                        crls[i].Length,
                        CERT_STORE_ADD_ALWAYS,
                        out crlContext))
                        return false;
                    crlContexts.Add(crlContext);
                }

                additionalStores = Marshal.AllocHGlobal(IntPtr.Size);
                Marshal.WriteIntPtr(additionalStores, memoryStore);
                CERT_CHAIN_ENGINE_CONFIG engineConfig = new CERT_CHAIN_ENGINE_CONFIG();
                engineConfig.cbSize = (uint)Marshal.SizeOf(typeof(CERT_CHAIN_ENGINE_CONFIG));
                engineConfig.hRestrictedOther = memoryStore;
                engineConfig.cAdditionalStore = 1;
                engineConfig.rghAdditionalStore = additionalStores;
                engineConfig.dwFlags = CERT_CHAIN_DISABLE_AUTH_ROOT_AUTO_UPDATE;
                engineConfig.dwUrlRetrievalTimeout = 0;
                if (!NativeMethods.CertCreateCertificateChainEngine(ref engineConfig, out chainEngine) ||
                    chainEngine == IntPtr.Zero)
                    return false;

                CERT_CHAIN_PARA chainParameters = new CERT_CHAIN_PARA();
                chainParameters.cbSize = (uint)Marshal.SizeOf(typeof(CERT_CHAIN_PARA));
                uint chainFlags = CERT_CHAIN_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT |
                                  CERT_CHAIN_REVOCATION_CHECK_CACHE_ONLY |
                                  CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL |
                                  CERT_CHAIN_DISABLE_AIA;
                if (!NativeMethods.CertGetCertificateChain(
                    chainEngine,
                    leaf.Handle,
                    IntPtr.Zero,
                    memoryStore,
                    ref chainParameters,
                    chainFlags,
                    IntPtr.Zero,
                    out chainContext) || chainContext == IntPtr.Zero)
                    return false;

                CERT_CHAIN_CONTEXT nativeChain = (CERT_CHAIN_CONTEXT)Marshal.PtrToStructure(
                    chainContext,
                    typeof(CERT_CHAIN_CONTEXT));
                if (nativeChain.TrustStatus.dwErrorStatus != 0) return false;

                SSL_EXTRA_CERT_CHAIN_POLICY_PARA sslExtra = new SSL_EXTRA_CERT_CHAIN_POLICY_PARA();
                sslExtra.cbSize = (uint)Marshal.SizeOf(typeof(SSL_EXTRA_CERT_CHAIN_POLICY_PARA));
                sslExtra.dwAuthType = AUTHTYPE_SERVER;
                sslExtra.fdwChecks = 0;
                serverNamePointer = Marshal.StringToHGlobalUni(serverName);
                sslExtra.pwszServerName = serverNamePointer;
                IntPtr sslExtraPointer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SSL_EXTRA_CERT_CHAIN_POLICY_PARA)));
                try
                {
                    Marshal.StructureToPtr(sslExtra, sslExtraPointer, false);
                    CERT_CHAIN_POLICY_PARA policyParameters = new CERT_CHAIN_POLICY_PARA();
                    policyParameters.cbSize = (uint)Marshal.SizeOf(typeof(CERT_CHAIN_POLICY_PARA));
                    policyParameters.dwFlags = 0;
                    policyParameters.pvExtraPolicyPara = sslExtraPointer;
                    CERT_CHAIN_POLICY_STATUS policyStatus = new CERT_CHAIN_POLICY_STATUS();
                    policyStatus.cbSize = (uint)Marshal.SizeOf(typeof(CERT_CHAIN_POLICY_STATUS));
                    if (!NativeMethods.CertVerifyCertificateChainPolicy(
                        CertChainPolicySsl,
                        chainContext,
                        ref policyParameters,
                        ref policyStatus))
                        return false;
                    return policyStatus.dwError == 0;
                }
                finally
                {
                    Marshal.FreeHGlobal(sslExtraPointer);
                }
            }
            catch
            {
                return false;
            }
            finally
            {
                if (serverNamePointer != IntPtr.Zero) Marshal.FreeHGlobal(serverNamePointer);
                if (chainContext != IntPtr.Zero) NativeMethods.CertFreeCertificateChain(chainContext);
                if (chainEngine != IntPtr.Zero) NativeMethods.CertFreeCertificateChainEngine(chainEngine);
                if (additionalStores != IntPtr.Zero) Marshal.FreeHGlobal(additionalStores);
                for (int i = 0; i < crlContexts.Count; i++)
                    if (crlContexts[i] != IntPtr.Zero) NativeMethods.CertFreeCRLContext(crlContexts[i]);
                if (memoryStore != IntPtr.Zero) NativeMethods.CertCloseStore(memoryStore, 0);
            }
        }

        private static bool BytesEqual(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            int different = 0;
            for (int i = 0; i < left.Length; i++) different |= left[i] ^ right[i];
            return different == 0;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_TRUST_STATUS
        {
            public uint dwErrorStatus;
            public uint dwInfoStatus;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_CHAIN_CONTEXT
        {
            public uint cbSize;
            public CERT_TRUST_STATUS TrustStatus;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_CHAIN_ENGINE_CONFIG
        {
            public uint cbSize;
            public IntPtr hRestrictedRoot;
            public IntPtr hRestrictedTrust;
            public IntPtr hRestrictedOther;
            public uint cAdditionalStore;
            public IntPtr rghAdditionalStore;
            public uint dwFlags;
            public uint dwUrlRetrievalTimeout;
            public uint MaximumCachedCertificates;
            public uint CycleDetectionModulus;
            public IntPtr hExclusiveRoot;
            public IntPtr hExclusiveTrustedPeople;
            public uint dwExclusiveFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_CHAIN_PARA
        {
            public uint cbSize;
            public CERT_USAGE_MATCH RequestedUsage;
            public CERT_USAGE_MATCH RequestedIssuancePolicy;
            public uint dwUrlRetrievalTimeout;
            public bool fCheckRevocationFreshnessTime;
            public uint dwRevocationFreshnessTime;
            public IntPtr pftCacheResync;
            public IntPtr pStrongSignPara;
            public uint dwStrongSignFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_USAGE_MATCH
        {
            public uint dwType;
            public CERT_ENHKEY_USAGE Usage;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_ENHKEY_USAGE
        {
            public uint cUsageIdentifier;
            public IntPtr rgpszUsageIdentifier;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SSL_EXTRA_CERT_CHAIN_POLICY_PARA
        {
            public uint cbSize;
            public uint dwAuthType;
            public uint fdwChecks;
            public IntPtr pwszServerName;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_CHAIN_POLICY_PARA
        {
            public uint cbSize;
            public uint dwFlags;
            public IntPtr pvExtraPolicyPara;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_CHAIN_POLICY_STATUS
        {
            public uint cbSize;
            public uint dwError;
            public int lChainIndex;
            public int lElementIndex;
            public IntPtr pvExtraPolicyStatus;
        }

        private static class NativeMethods
        {
            [DllImport("crypt32.dll", SetLastError = true)]
            internal static extern IntPtr CertOpenStore(
                IntPtr lpszStoreProvider,
                uint dwEncodingType,
                IntPtr hCryptProv,
                uint dwFlags,
                IntPtr pvPara);

            [DllImport("crypt32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertCloseStore(IntPtr hCertStore, uint dwFlags);

            [DllImport("crypt32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertAddCertificateContextToStore(
                IntPtr hCertStore,
                IntPtr pCertContext,
                uint dwAddDisposition,
                IntPtr ppStoreContext);

            [DllImport("crypt32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertAddEncodedCRLToStore(
                IntPtr hCertStore,
                uint dwCertEncodingType,
                byte[] pbCrlEncoded,
                int cbCrlEncoded,
                uint dwAddDisposition,
                out IntPtr ppCrlContext);

            [DllImport("crypt32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertFreeCRLContext(IntPtr pCrlContext);

            [DllImport("crypt32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertCreateCertificateChainEngine(
                ref CERT_CHAIN_ENGINE_CONFIG pConfig,
                out IntPtr phChainEngine);

            [DllImport("crypt32.dll")]
            internal static extern void CertFreeCertificateChainEngine(IntPtr hChainEngine);

            [DllImport("crypt32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertGetCertificateChain(
                IntPtr hChainEngine,
                IntPtr pCertContext,
                IntPtr pTime,
                IntPtr hAdditionalStore,
                ref CERT_CHAIN_PARA pChainPara,
                uint dwFlags,
                IntPtr pvReserved,
                out IntPtr ppChainContext);

            [DllImport("crypt32.dll")]
            internal static extern void CertFreeCertificateChain(IntPtr pChainContext);

            [DllImport("crypt32.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            internal static extern bool CertVerifyCertificateChainPolicy(
                IntPtr pszPolicyOID,
                IntPtr pChainContext,
                ref CERT_CHAIN_POLICY_PARA pPolicyPara,
                ref CERT_CHAIN_POLICY_STATUS pPolicyStatus);
        }
    }
}
'@
}

function New-StrictSmtpTlsValidationCallback(
  [Parameter(Mandatory = $true)][string]$ServerName,
  [ValidateRange(1000, 12000)][int]$DownloadBudgetMs = 12000
) {
  Initialize-StrictSmtpTlsValidation
  return [HereIam.ICore.Security.StrictSmtpTlsValidation]::CreateCallback(
    $ServerName,
    $DownloadBudgetMs
  )
}
