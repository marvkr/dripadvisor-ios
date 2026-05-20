// Package scrape wraps the self-hosted Camoufox anti-detection browser
// running on the Hetzner box. Lets us scrape JS-heavy ecom (Lululemon,
// Zara, Nike) from the backend without Firecrawl or paid services.
//
// Lifecycle for one scrape:
//   tabId := Open(ctx, url)
//   defer Close(ctx, tabId)
//   Wait(ctx, tabId, 6000)
//   result := Evaluate(ctx, tabId, jsExpression)
package scrape

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Camofox is the wrapper. Configure via CAMOFOX_URL (default
// http://host.docker.internal:9377). No auth required when the server runs
// without CAMOFOX_API_KEY / CAMOFOX_ACCESS_KEY set.
type Camofox struct {
	baseURL string
	userID  string
	client  *http.Client
}

func NewCamofox(baseURL string) *Camofox {
	if baseURL == "" {
		baseURL = "http://host.docker.internal:9377"
	}
	return &Camofox{
		baseURL: baseURL,
		userID:  "drip-backend",
		client:  &http.Client{Timeout: 30 * time.Second},
	}
}

// Available pings /health to see if Camofox is reachable + the browser is up.
func (c *Camofox) Available(ctx context.Context) bool {
	if c == nil {
		return false
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/health", nil)
	if err != nil {
		return false
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	var body struct {
		OK               bool `json:"ok"`
		BrowserConnected bool `json:"browserConnected"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&body)
	return body.OK && body.BrowserConnected
}

type openResp struct {
	TabID string `json:"tabId"`
	Error string `json:"error,omitempty"`
}

func (c *Camofox) openTab(ctx context.Context, url string) (string, error) {
	body, _ := json.Marshal(map[string]any{
		"userId":     c.userID,
		"sessionKey": "scrape",
		"url":        url,
	})
	var out openResp
	if err := c.post(ctx, "/tabs", body, &out); err != nil {
		return "", err
	}
	if out.Error != "" {
		return "", errors.New(out.Error)
	}
	if out.TabID == "" {
		return "", errors.New("camofox: empty tabId")
	}
	return out.TabID, nil
}

func (c *Camofox) closeTab(ctx context.Context, tabID string) {
	body, _ := json.Marshal(map[string]any{"userId": c.userID})
	req, _ := http.NewRequestWithContext(ctx, http.MethodDelete, c.baseURL+"/tabs/"+tabID, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if resp, err := c.client.Do(req); err == nil {
		resp.Body.Close()
	}
}

func (c *Camofox) wait(ctx context.Context, tabID string, timeoutMs int) error {
	body, _ := json.Marshal(map[string]any{
		"userId":  c.userID,
		"timeout": timeoutMs,
	})
	return c.post(ctx, "/tabs/"+tabID+"/wait", body, nil)
}

type evalResp struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result"`
	Error  string          `json:"error,omitempty"`
}

// Evaluate runs JS in the tab and returns the raw JSON result.
func (c *Camofox) evaluate(ctx context.Context, tabID, expression string) (json.RawMessage, error) {
	body, _ := json.Marshal(map[string]any{
		"userId":     c.userID,
		"expression": expression,
	})
	var out evalResp
	if err := c.post(ctx, "/tabs/"+tabID+"/evaluate", body, &out); err != nil {
		return nil, err
	}
	if out.Error != "" {
		return nil, errors.New(out.Error)
	}
	return out.Result, nil
}

// ScrapeProduct opens the URL in Camofox, waits for JS, extracts OG tags +
// schema.org product JSON-LD, and returns a normalized result. Empty strings
// mean the field was not found.
type ProductResult struct {
	Name        string  `json:"name"`
	Brand       string  `json:"brand"`
	ImageURL    string  `json:"image_url"`
	RetailPrice float64 `json:"retail_price"`
	Currency    string  `json:"currency"`
}

const productExtractJS = `(() => {
  const meta = (sel) => document.querySelector(sel)?.content || '';
  let name = meta('meta[property="og:title"]') || document.title || '';
  const image = meta('meta[property="og:image"]') ||
                document.querySelector('img[data-zoomimg], img[itemprop="image"]')?.src || '';
  let brand = meta('meta[property="og:site_name"]') || '';
  let price = parseFloat(meta('meta[property="product:price:amount"]')) || 0;
  let currency = meta('meta[property="product:price:currency"]') || '';

  // Schema.org Product JSON-LD often has cleaner data.
  for (const s of document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      const arr = (() => { const d = JSON.parse(s.textContent); return Array.isArray(d) ? d : [d]; })();
      for (const d of arr) {
        const types = Array.isArray(d['@type']) ? d['@type'] : [d['@type']];
        if (!types.includes('Product')) continue;
        if (!name && d.name) name = d.name;
        if (!brand && d.brand) brand = (typeof d.brand === 'string' ? d.brand : d.brand?.name || '');
        const offers = Array.isArray(d.offers) ? d.offers[0] : d.offers;
        if (offers) {
          if (!price && offers.price) price = parseFloat(offers.price);
          if (!currency && offers.priceCurrency) currency = offers.priceCurrency;
        }
      }
    } catch {}
  }
  return { name: name.trim(), brand: brand.trim(), image_url: image, retail_price: price, currency };
})()`

// ScrapeProduct does the full open/wait/evaluate/close dance for a URL.
func (c *Camofox) ScrapeProduct(ctx context.Context, url string) (*ProductResult, error) {
	if c == nil {
		return nil, errors.New("camofox: not configured")
	}
	tabID, err := c.openTab(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("open tab: %w", err)
	}
	defer c.closeTab(context.Background(), tabID)

	if err := c.wait(ctx, tabID, 5000); err != nil {
		// Wait can timeout; we still try to evaluate — the page may have loaded enough.
	}

	raw, err := c.evaluate(ctx, tabID, productExtractJS)
	if err != nil {
		return nil, fmt.Errorf("evaluate: %w", err)
	}
	var r ProductResult
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("decode: %w (raw: %s)", err, string(raw))
	}
	return &r, nil
}

func (c *Camofox) post(ctx context.Context, path string, body []byte, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		buf, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("camofox %s: %d %s", path, resp.StatusCode, string(buf))
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}
