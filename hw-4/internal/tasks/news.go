package tasks

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"hw-4/internal/cache"
)

const newsCacheTTL = 10 * time.Minute

func FetchNews(apiKey, query string, cm *cache.Manager) error {
	cacheKey := fmt.Sprintf("news:%s", query)

	if cm != nil {
		cached, err := cm.Get(cacheKey)
		if err == nil && cached != "" {
			var data newsData
			if json.Unmarshal([]byte(cached), &data) == nil {
				fmt.Printf("[CACHE HIT] News for %q: %d results\n", query, data.TotalResults)
				for i, a := range data.Articles {
					fmt.Printf("  %d. [%s] %s\n", i+1, a.Source.Name, a.Title)
				}
				return nil
			}
		}
	}

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

	var data newsData
	if err := json.Unmarshal(body, &data); err != nil {
		return fmt.Errorf("parse news JSON: %w", err)
	}

	fmt.Printf("[API CALL] News for %q: %d results\n", query, data.TotalResults)
	for i, a := range data.Articles {
		fmt.Printf("  %d. [%s] %s\n", i+1, a.Source.Name, a.Title)
	}

	if cm != nil {
		if err := cm.Set(cacheKey, string(body), newsCacheTTL); err != nil {
			fmt.Printf("[WARN] cache set: %v\n", err)
		} else {
			fmt.Printf("[CACHE SET] key=%s ttl=%s\n", cacheKey, newsCacheTTL)
		}
	}

	return nil
}

type newsData struct {
	TotalResults int `json:"totalResults"`
	Articles     []struct {
		Title  string `json:"title"`
		Source struct {
			Name string `json:"name"`
		} `json:"source"`
	} `json:"articles"`
}
