return {
  quickLinks = {
    {
      name = "Search Google",
      link = "https://google.com/search?q={query}",
    },
    {
      name = "Search DuckDuckGo",
      link = "https://duckduckgo.com/?q={query}",
    },
    {
      name = "Ask Google",
      link = "https://google.com/search?q={query}&udm=50",
    },
    {
      name = "Ask Grok",
      link = "https://grok.com/?q={query}",
    },
    {
      name = "Ask ChatGPT",
      link = "https://chatgpt.com/?q={query}&temporary-chat=true&model=gpt-5-instant",
    },
    {
      name = "Ask All",
      links = {
        "https://google.com/search?q={query}&udm=50",
        "https://grok.com/?q={query}",
        "https://chatgpt.com/?q={query}&temporary-chat=true&model=gpt-5-instant",
      },
    },
    {
      name = "Goto Github",
      link = "https://github.com/Cryptact/cryptact/pull/{query}",
    },
    {
      iconName = "computer-chip-16",
      name = "Goto YouTrack",
      link = "https://cryptact.myjetbrains.com/youtrack/issue/GRID-{query}",
    },
  },
}
