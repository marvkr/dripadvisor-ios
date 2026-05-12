package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const appleJWKSURL = "https://appleid.apple.com/auth/keys"

// AppleVerifier validates Sign In with Apple identity tokens against Apple's JWKS.
type AppleVerifier struct {
	BundleID string
	client   *http.Client

	mu       sync.Mutex
	keys     map[string]*rsa.PublicKey
	fetched  time.Time
	cacheTTL time.Duration
}

func NewAppleVerifier(bundleID string) *AppleVerifier {
	return &AppleVerifier{
		BundleID: bundleID,
		client:   &http.Client{Timeout: 5 * time.Second},
		keys:     map[string]*rsa.PublicKey{},
		cacheTTL: time.Hour,
	}
}

// AppleClaims is a subset of the identity token payload we care about.
type AppleClaims struct {
	Email         string `json:"email,omitempty"`
	EmailVerified any    `json:"email_verified,omitempty"`
	IsPrivateEmail any   `json:"is_private_email,omitempty"`
	jwt.RegisteredClaims
}

// Verify validates an Apple identity token and returns its claims.
func (v *AppleVerifier) Verify(ctx context.Context, identityToken string) (*AppleClaims, error) {
	parsed, err := jwt.ParseWithClaims(identityToken, &AppleClaims{}, func(t *jwt.Token) (any, error) {
		if t.Method.Alg() != "RS256" {
			return nil, fmt.Errorf("unexpected alg %q", t.Method.Alg())
		}
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, errors.New("missing kid")
		}
		return v.keyFor(ctx, kid)
	},
		jwt.WithIssuer("https://appleid.apple.com"),
		jwt.WithAudience(v.BundleID),
		jwt.WithValidMethods([]string{"RS256"}),
	)
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*AppleClaims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid apple claims")
	}
	return claims, nil
}

type jwk struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type jwks struct {
	Keys []jwk `json:"keys"`
}

func (v *AppleVerifier) keyFor(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	if k, ok := v.keys[kid]; ok && time.Since(v.fetched) < v.cacheTTL {
		return k, nil
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, appleJWKSURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("apple jwks: status %d", resp.StatusCode)
	}
	var set jwks
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, err
	}

	v.keys = make(map[string]*rsa.PublicKey, len(set.Keys))
	for _, k := range set.Keys {
		nB, err := base64.RawURLEncoding.DecodeString(k.N)
		if err != nil {
			continue
		}
		eB, err := base64.RawURLEncoding.DecodeString(k.E)
		if err != nil {
			continue
		}
		e := 0
		for _, b := range eB {
			e = e<<8 | int(b)
		}
		v.keys[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(nB), E: e}
	}
	v.fetched = time.Now()

	if k, ok := v.keys[kid]; ok {
		return k, nil
	}
	return nil, fmt.Errorf("unknown apple kid %q", kid)
}
