package tasks

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
)

func FetchNews(apiKey, query string) error {
	url := fmt.Sprintf(
		"https://newsapi.org/v2/everything?q=%s&apiKey=%s&pageSize=5",
		query, apiKey,
	)

	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("news request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read news response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("news API %s: %s", resp.Status, string(body))
	}

	var data struct {
		TotalResults int `json:"totalResults"`
		Articles     []struct {
			Title  string `json:"title"`
			Source struct {
				Name string `json:"name"`
			} `json:"source"`
		} `json:"articles"`
	}
	if err := json.Unmarshal(body, &data); err != nil {
		return fmt.Errorf("parse news JSON: %w", err)
	}

	fmt.Printf("[OK] News for %q: %d results found\n", query, data.TotalResults)
	for i, a := range data.Articles {
		fmt.Printf("  %d. [%s] %s\n", i+1, a.Source.Name, a.Title)
	}

	if err := os.WriteFile("news_result.json", body, 0644); err != nil {
		return fmt.Errorf("write news_result.json: %w", err)
	}
	return nil
}
