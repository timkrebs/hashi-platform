package vault

import "testing"

func TestSplitSignature(t *testing.T) {
	// Transit returns "vault:v<n>:<base64>", not a bare signature. Stripping
	// this wrongly produces a token that no verifier accepts.
	tests := []struct {
		name    string
		in      string
		version int
		sig     string
		wantErr bool
	}{
		{name: "version 1", in: "vault:v1:YWJj", version: 1, sig: "YWJj"},
		{name: "rotated key", in: "vault:v42:YWJj", version: 42, sig: "YWJj"},
		// Base64 contains no colon, but a payload with padding must survive
		// SplitN's limit of three.
		{name: "padded payload", in: "vault:v2:YWJjZA==", version: 2, sig: "YWJjZA=="},
		{name: "missing prefix", in: "v1:YWJj", wantErr: true},
		{name: "not vault", in: "other:v1:YWJj", wantErr: true},
		{name: "bad version", in: "vault:vx:YWJj", wantErr: true},
		{name: "empty", in: "", wantErr: true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			version, sig, err := splitSignature(tc.in)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected an error for %q", tc.in)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if version != tc.version || sig != tc.sig {
				t.Errorf("got (%d, %q), want (%d, %q)", version, sig, tc.version, tc.sig)
			}
		})
	}
}

func TestParseRSAPublicKeyRejectsNonPEM(t *testing.T) {
	if _, err := parseRSAPublicKey("not a pem block"); err == nil {
		t.Fatal("expected an error for non-PEM input")
	}
}
