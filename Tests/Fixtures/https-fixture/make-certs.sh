#!/bin/bash
# Makes the two self-signed test certificates of the https fixture and the SPKI hash Brk's test switch trusts.
#
#   Tests/Fixtures/https-fixture/make-certs.sh
#
# trusted.pem    127.0.0.1, localhost and secure.brk.test. Brk trusts it only when launched with
#                BRK_CONTROL_SOCKET and BRK_TEST_TRUSTED_SPKI=$(cat trusted.spki), which passes Chromium's
#                --ignore-certificate-errors-spki-list for this one key. Nothing is added to a keychain or to
#                the system trust settings.
# untrusted.pem  untrusted.brk.test, a different key that nothing trusts: Chromium shows its certificate
#                interstitial and, after Proceed, holds a certificate error against the page.
#
# The files are committed so runs are repeatable; rerun this only to replace them.
set -euo pipefail
cd "$(dirname "$0")"
make() {
  local name="$1" subject="$2" names="$3"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
    -keyout "$name-key.pem" -out "$name.pem" -subj "/CN=$subject" \
    -addext "subjectAltName=$names" -addext "basicConstraints=critical,CA:FALSE" \
    -addext "extendedKeyUsage=serverAuth" 2>/dev/null
}
make trusted "Brk test fixture (trusted by the test switch)" "IP:127.0.0.1,DNS:localhost,DNS:secure.brk.test"
make untrusted "untrusted.brk.test" "DNS:untrusted.brk.test"
# Chromium's format: base64 of the SHA-256 of the DER SubjectPublicKeyInfo.
openssl x509 -in trusted.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64 > trusted.spki
echo "trusted SPKI: $(cat trusted.spki)"
