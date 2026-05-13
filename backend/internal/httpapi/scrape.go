package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"golang.org/x/net/html"
)

// /v1/wardrobe/scrape — extracts product metadata from a pasted URL so the
// client can preview before saving as a wishlist item. Lightweight v1: fetch
// page, parse OG tags + schema.org product JSON-LD if present. Firecrawl
// integration is a v1.1 upgrade for JS-heavy sites.

type scrapeReq struct {
	URL string `json:"url"`
}

type scrapeResp struct {
	Name        *string  `json:"name,omitempty"`
	Brand       *string  `json:"brand,omitempty"`
	ImageURL    *string  `json:"image_url,omitempty"`
	RetailPrice *float64 `json:"retail_price,omitempty"`
	Currency    *string  `json:"currency,omitempty"`
	SourceURL   string   `json:"source_url"`
}

func handleScrapeWardrobe(_ *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req scrapeReq
		if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		u, err := validateScrapeURL(req.URL)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		defer cancel()

		body, err := fetchPage(ctx, u.String())
		if err != nil {
			writeError(w, http.StatusBadGateway, "fetch failed")
			return
		}
		resp := parseProduct(body)
		resp.SourceURL = u.String()
		writeJSON(w, http.StatusOK, resp)
	}
}

func validateScrapeURL(raw string) (*url.URL, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, errors.New("url required")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nil, errors.New("invalid url")
	}
	if u.Scheme != "https" && u.Scheme != "http" {
		return nil, errors.New("only http(s) urls")
	}
	if u.Host == "" || strings.Contains(u.Host, "localhost") || strings.HasPrefix(u.Host, "127.") {
		return nil, errors.New("invalid host")
	}
	return u, nil
}

func fetchPage(ctx context.Context, target string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent",
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")
	req.Header.Set("Accept", "text/html,application/xhtml+xml")
	client := &http.Client{Timeout: 12 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode >= 400 {
		return nil, errors.New("non-2xx")
	}
	return io.ReadAll(io.LimitReader(resp.Body, 2<<20))
}

// parseProduct walks the HTML tree once, pulling whichever OG / Twitter /
// schema.org signals are present. Best-effort; missing fields stay nil.
func parseProduct(body []byte) scrapeResp {
	var out scrapeResp
	doc, err := html.Parse(strings.NewReader(string(body)))
	if err != nil {
		return out
	}
	walk(doc, &out)
	return out
}

func walk(n *html.Node, out *scrapeResp) {
	if n.Type == html.ElementNode {
		switch n.Data {
		case "meta":
			absorbMeta(n, out)
		case "title":
			if out.Name == nil && n.FirstChild != nil {
				t := strings.TrimSpace(n.FirstChild.Data)
				if t != "" {
					out.Name = &t
				}
			}
		case "script":
			if attrEq(n, "type", "application/ld+json") && n.FirstChild != nil {
				absorbLD(n.FirstChild.Data, out)
			}
		}
	}
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		walk(c, out)
	}
}

func absorbMeta(n *html.Node, out *scrapeResp) {
	prop := strings.ToLower(getAttr(n, "property"))
	name := strings.ToLower(getAttr(n, "name"))
	content := strings.TrimSpace(getAttr(n, "content"))
	if content == "" {
		return
	}
	switch {
	case prop == "og:title" || name == "twitter:title":
		if out.Name == nil {
			out.Name = &content
		}
	case prop == "og:image" || name == "twitter:image" || prop == "og:image:secure_url":
		if out.ImageURL == nil {
			out.ImageURL = &content
		}
	case prop == "og:site_name":
		if out.Brand == nil {
			out.Brand = &content
		}
	case prop == "product:price:amount" || prop == "og:price:amount":
		if v, err := strconv.ParseFloat(content, 64); err == nil && out.RetailPrice == nil {
			out.RetailPrice = &v
		}
	case prop == "product:price:currency" || prop == "og:price:currency":
		up := strings.ToUpper(content)
		if out.Currency == nil && len(up) == 3 {
			out.Currency = &up
		}
	}
}

// Very small JSON-LD product parser. Only pulls top-level name / brand /
// image / offers.price. Real schema is deeply nested with @graph + arrays;
// this catches the simple e-commerce templates (Lululemon, Nike, Shopify
// stores) which are the v1 target.
var priceRE = regexp.MustCompile(`"price"\s*:\s*"?(\d+\.?\d*)"?`)

func absorbLD(blob string, out *scrapeResp) {
	var raw map[string]any
	if err := json.Unmarshal([]byte(blob), &raw); err != nil {
		// Most pages embed an array; try that.
		var arr []map[string]any
		if err2 := json.Unmarshal([]byte(blob), &arr); err2 != nil {
			absorbPriceFallback(blob, out)
			return
		}
		for _, m := range arr {
			absorbLDNode(m, out)
		}
		return
	}
	absorbLDNode(raw, out)
}

func absorbLDNode(node map[string]any, out *scrapeResp) {
	if s, ok := node["name"].(string); ok && out.Name == nil {
		out.Name = &s
	}
	if b, ok := node["brand"]; ok && out.Brand == nil {
		switch v := b.(type) {
		case string:
			out.Brand = &v
		case map[string]any:
			if n, ok := v["name"].(string); ok {
				out.Brand = &n
			}
		}
	}
	if img, ok := node["image"]; ok && out.ImageURL == nil {
		switch v := img.(type) {
		case string:
			out.ImageURL = &v
		case []any:
			if len(v) > 0 {
				if s, ok := v[0].(string); ok {
					out.ImageURL = &s
				}
			}
		}
	}
	if offers, ok := node["offers"]; ok {
		switch v := offers.(type) {
		case map[string]any:
			absorbOffer(v, out)
		case []any:
			for _, o := range v {
				if m, ok := o.(map[string]any); ok {
					absorbOffer(m, out)
				}
			}
		}
	}
}

func absorbOffer(o map[string]any, out *scrapeResp) {
	if p, ok := o["price"]; ok && out.RetailPrice == nil {
		switch v := p.(type) {
		case string:
			if f, err := strconv.ParseFloat(v, 64); err == nil {
				out.RetailPrice = &f
			}
		case float64:
			out.RetailPrice = &v
		}
	}
	if c, ok := o["priceCurrency"].(string); ok && out.Currency == nil && len(c) == 3 {
		up := strings.ToUpper(c)
		out.Currency = &up
	}
}

func absorbPriceFallback(blob string, out *scrapeResp) {
	if out.RetailPrice != nil {
		return
	}
	m := priceRE.FindStringSubmatch(blob)
	if len(m) == 2 {
		if v, err := strconv.ParseFloat(m[1], 64); err == nil {
			out.RetailPrice = &v
		}
	}
}

func getAttr(n *html.Node, key string) string {
	for _, a := range n.Attr {
		if a.Key == key {
			return a.Val
		}
	}
	return ""
}

func attrEq(n *html.Node, key, val string) bool {
	return strings.EqualFold(getAttr(n, key), val)
}
