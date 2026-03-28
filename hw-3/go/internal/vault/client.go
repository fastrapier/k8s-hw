package vault

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

type Client struct {
	addr  string
	token string
	http  *http.Client
}

func NewClient() (*Client, error) {
	addr := os.Getenv("VAULT_ADDR")
	if addr == "" {
		addr = "http://vault.local"
	}
	addr = strings.TrimRight(addr, "/")

	token := os.Getenv("VAULT_TOKEN")
	roleID := os.Getenv("VAULT_ROLE_ID")
	secretID := os.Getenv("VAULT_SECRET_ID")

	c := &Client{addr: addr, http: &http.Client{}}

	if token != "" {
		c.token = token
		return c, nil
	}

	if roleID != "" && secretID != "" {
		tok, err := c.loginAppRole(roleID, secretID)
		if err != nil {
			return nil, fmt.Errorf("approle login: %w", err)
		}
		c.token = tok
		return c, nil
	}

	return nil, fmt.Errorf("set VAULT_TOKEN or (VAULT_ROLE_ID + VAULT_SECRET_ID)")
}

func (c *Client) loginAppRole(roleID, secretID string) (string, error) {
	body := fmt.Sprintf(`{"role_id":%q,"secret_id":%q}`, roleID, secretID)
	resp, err := c.http.Post(
		c.addr+"/v1/auth/approle/login",
		"application/json",
		strings.NewReader(body),
	)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Auth struct {
			ClientToken string `json:"client_token"`
		} `json:"auth"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if result.Auth.ClientToken == "" {
		return "", fmt.Errorf("empty client_token in approle response")
	}
	return result.Auth.ClientToken, nil
}

// GetSecret reads a KV-v2 secret at the given path and returns the value for key.
// path should be like "secret/rabbitmq"; the /v1/secret/data/ prefix is added automatically.
func (c *Client) GetSecret(path, key string) (string, error) {
	// KV v2: secret/rabbitmq -> /v1/secret/data/rabbitmq
	parts := strings.SplitN(path, "/", 2)
	if len(parts) != 2 {
		return "", fmt.Errorf("invalid secret path %q, expected mount/path", path)
	}
	url := fmt.Sprintf("%s/v1/%s/data/%s", c.addr, parts[0], parts[1])

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("X-Vault-Token", c.token)

	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("vault %s: %s %s", url, resp.Status, string(b))
	}

	var result struct {
		Data struct {
			Data map[string]interface{} `json:"data"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}

	val, ok := result.Data.Data[key]
	if !ok {
		return "", fmt.Errorf("key %q not found at %s", key, path)
	}
	return fmt.Sprint(val), nil
}
