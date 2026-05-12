package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// Claims is the DripAdvisor session JWT payload.
type Claims struct {
	UserID uuid.UUID `json:"uid"`
	jwt.RegisteredClaims
}

type Signer struct {
	secret  []byte
	ttl     time.Duration
	issuer  string
}

func NewSigner(secret string, ttlHours int) *Signer {
	return &Signer{
		secret: []byte(secret),
		ttl:    time.Duration(ttlHours) * time.Hour,
		issuer: "dripadvisor",
	}
}

func (s *Signer) Issue(userID uuid.UUID) (string, time.Time, error) {
	now := time.Now()
	exp := now.Add(s.ttl)
	claims := Claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    s.issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
			Subject:   userID.String(),
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := t.SignedString(s.secret)
	return signed, exp, err
}

func (s *Signer) Verify(raw string) (*Claims, error) {
	parsed, err := jwt.ParseWithClaims(raw, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return s.secret, nil
	}, jwt.WithIssuer(s.issuer), jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid claims")
	}
	return claims, nil
}
