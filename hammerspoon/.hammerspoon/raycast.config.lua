return {
  quickLinks = {
    {
      name = "Ask Google",
      link = "https://google.com/search?q={query}&udm=50",
    },
    {
      name = "Ask ChatGPT",
      link = "https://chatgpt.com/?q={query}&temporary-chat=true&model=gpt-5-instant",
    },
    {
      name = "Ask Grok",
      link = "https://grok.com/?q={query}",
    },
    {
      name = "Ask All",
      links = {
        "https://grok.com/?q={query}",
        "https://chatgpt.com/?q={query}&temporary-chat=true&model=gpt-5-instant",
        "https://google.com/search?q={query}&udm=50",
      },
    },
    {
      name = "Search Google",
      link = "https://google.com/search?q={query}",
    },
    {
      name = "Search DuckDuckGo",
      link = "https://duckduckgo.com/?q={query}",
    },
  },
}
