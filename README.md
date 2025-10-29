# Reddit Viewer

A Phoenix web application for viewing Reddit posts and user post history.

## Structure

- `reddit_viewer/` - The main Phoenix application
- `docs/` - Reddit API documentation
- `posturl.txt` - Example Reddit post URL
- `credentials` - Reddit API credentials (not tracked in git)

## Setup

1. Navigate to the Phoenix app:
   ```bash
   cd reddit_viewer
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Set up Reddit API credentials:
   - Create a Reddit app at https://www.reddit.com/prefs/apps
   - Copy `credentials` file and update with your app credentials

4. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

The application will be available at http://localhost:6000

## Features

- Input a Reddit post URL to fetch post information
- View post details (title, author, subreddit, upvotes, etc.)
- View the post author's recent post history in a table format
- Rate limiting to stay under Reddit API limits (< 50 requests per minute)

## Usage

1. Open the application in your browser
2. Paste a Reddit post URL in the input field
3. Click "Fetch Post" to retrieve the post information
4. The post details and author's post history will be displayed below
