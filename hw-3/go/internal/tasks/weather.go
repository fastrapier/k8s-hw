package tasks

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
)

func FetchWeather(apiKey, city string) error {
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

	var data struct {
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
	if err := json.Unmarshal(body, &data); err != nil {
		return fmt.Errorf("parse weather JSON: %w", err)
	}

	desc := ""
	if len(data.Weather) > 0 {
		desc = data.Weather[0].Description
	}
	fmt.Printf("[OK] Weather: %s | %.1f°C (feels %.1f°C) | %s | humidity %d%% | wind %.1f m/s\n",
		data.Name, data.Main.Temp, data.Main.FeelsLike, desc, data.Main.Humidity, data.Wind.Speed)

	if err := os.WriteFile("weather_result.json", body, 0644); err != nil {
		return fmt.Errorf("write weather_result.json: %w", err)
	}
	return nil
}
