package tasks

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"hw-4/internal/cache"
)

const weatherCacheTTL = 5 * time.Minute

func FetchWeather(apiKey, city string, cm *cache.Manager) error {
	cacheKey := fmt.Sprintf("weather:%s", city)

	if cm != nil {
		cached, err := cm.Get(cacheKey)
		if err == nil && cached != "" {
			var data weatherData
			if json.Unmarshal([]byte(cached), &data) == nil {
				desc := ""
				if len(data.Weather) > 0 {
					desc = data.Weather[0].Description
				}
				fmt.Printf("[CACHE HIT] Weather: %s | %.1f°C (feels %.1f°C) | %s | humidity %d%% | wind %.1f m/s\n",
					data.Name, data.Main.Temp, data.Main.FeelsLike, desc, data.Main.Humidity, data.Wind.Speed)
				return nil
			}
		}
	}

	url := fmt.Sprintf(
		"https://api.openweathermap.org/data/2.5/weather?q=%s&appid=%s&units=metric",
		city, apiKey,
	)

	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("weather request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read weather response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("weather API %s: %s", resp.Status, string(body))
	}

	var data weatherData
	if err := json.Unmarshal(body, &data); err != nil {
		return fmt.Errorf("parse weather JSON: %w", err)
	}

	desc := ""
	if len(data.Weather) > 0 {
		desc = data.Weather[0].Description
	}
	fmt.Printf("[API CALL] Weather: %s | %.1f°C (feels %.1f°C) | %s | humidity %d%% | wind %.1f m/s\n",
		data.Name, data.Main.Temp, data.Main.FeelsLike, desc, data.Main.Humidity, data.Wind.Speed)

	if cm != nil {
		if err := cm.Set(cacheKey, string(body), weatherCacheTTL); err != nil {
			fmt.Printf("[WARN] cache set: %v\n", err)
		} else {
			fmt.Printf("[CACHE SET] key=%s ttl=%s\n", cacheKey, weatherCacheTTL)
		}
	}

	return nil
}

type weatherData struct {
	Name string `json:"name"`
	Main struct {
		Temp      float64 `json:"temp"`
		FeelsLike float64 `json:"feels_like"`
		Humidity  int     `json:"humidity"`
	} `json:"main"`
	Weather []struct {
		Description string `json:"description"`
	} `json:"weather"`
	Wind struct {
		Speed float64 `json:"speed"`
	} `json:"wind"`
}
