# Environment Variables Setup

## OpenAI API Key

You need to set the `OPENAI_API_KEY` environment variable. You have several options:

### Option 1: Export in your shell
```bash
export OPENAI_API_KEY="your_api_key_here"
```

### Option 2: Add to ~/.bashrc or ~/.zshrc
```bash
echo 'export OPENAI_API_KEY="your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

### Option 3: Use a .env file (recommended for development)
Create a `.env` file in the project root:
```
OPENAI_API_KEY=your_api_key_here
```

Then load it when starting the application:
```bash
source .env && mix phx.server
```

### Option 4: Use direnv
Install direnv and create a `.envrc` file:
```bash
export OPENAI_API_KEY="your_api_key_here"
```

## Reddit API Credentials

The application already uses these environment variables:
- `REDDIT_APP_ID`
- `REDDIT_APP_SECRET`

Set them the same way as the OpenAI key if you want to use your own credentials.
