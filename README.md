# TrainsAPI — Gautrain Transit Timetable API

A high-performance Sinatra/Rack microservice for live Gautrain timetables, routes, fare estimations, and station information.

## 🚀 Quick Start

### 1. Prerequisites
- **Ruby**: Version 3.2+
- **Bundler**: `gem install bundler`

### 2. Installation
Navigate into the application folder and install dependencies:
```bash
cd TrainTimesAPI
bundle install
```

### 3. Environment Configuration
Ensure `.env` exists in `TrainTimesAPI/`:
```env
API_KEY=change-me-to-something-strong
```

### 4. Running the Server

#### Option A: Using the Executable Script (Recommended)
```bash
cd TrainTimesAPI
./bin/start
```

#### Option B: Using Rackup / Puma directly
```bash
cd TrainTimesAPI
bundle exec rackup -p 9292
```

#### Option C: Development Mode (Auto-Reloading)
```bash
cd TrainTimesAPI
bundle exec rerun 'rackup -p 9292'
```

The API runs locally on **`http://localhost:9292`**.

---

## 📖 API Documentation

Interactive API Reference & Contract documentation is hosted directly by the server:
- Open [http://localhost:9292/api_docs.html](http://localhost:9292/api_docs.html) in your browser.
- Or view the static file at [`TrainTimesAPI/public/api_docs.html`](file:///Users/pat@glucode.com/Documents/GitHub/TrainsAPI/TrainTimesAPI/public/api_docs.html).

---

## 🧪 Testing

Run the automated test suite with Minitest:
```bash
cd TrainTimesAPI
bundle exec ruby -Ilib -Itest test/journeys_test.rb
```

---

## 📡 Example cURL Requests

```bash
# Health Check (Public)
curl -i http://localhost:9292/health

# Fetch Stations (Requires X-Api-Key)
curl -i -H "X-Api-Key: change-me-to-something-strong" \
  http://localhost:9292/v1/stations

# Query Journeys
curl -i -H "X-Api-Key: change-me-to-something-strong" \
  "http://localhost:9292/v1/journeys?from=rosebank&to=marlboro"
```
