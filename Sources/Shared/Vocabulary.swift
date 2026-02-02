import Foundation

/// A vocabulary term with metadata
public struct VocabTerm: Codable, Identifiable, Hashable {
    public let id: UUID
    public var term: String
    public var category: String
    public var enabled: Bool

    public init(term: String, category: String, enabled: Bool = true) {
        self.id = UUID()
        self.term = term
        self.category = category
        self.enabled = enabled
    }
}

/// Manages custom vocabulary for transcription context
public final class Vocabulary {
    public static let shared = Vocabulary()

    private var terms: [VocabTerm] = []
    private let fileURL: URL

    /// All defined categories
    public static let categories = [
        "Software Engineering",
        "JavaScript/TypeScript",
        "Frontend",
        "Hip-Hop",
        "Houston/Texas",
        "Louisiana/NOLA",
        "Track & Field",
        "Basketball",
        "Sports",
        "Stand-Up Comedy",
        "Pop Culture",
        "Southern Slang",
        "Custom"
    ]

    private init() {
        let baseURL = SharedStorage.baseDirectory()
        let appDir = baseURL.appendingPathComponent("Whisper", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        fileURL = appDir.appendingPathComponent("vocabulary.json")
        load()

        // Initialize with presets if empty
        if terms.isEmpty {
            loadAllPresets()
            save()
        }
    }

    // MARK: - Public API

    /// Get all terms
    public var allTerms: [VocabTerm] { terms }

    /// Get terms by category
    public func terms(in category: String) -> [VocabTerm] {
        terms.filter { $0.category == category }
    }

    /// Get enabled terms only
    public var enabledTerms: [VocabTerm] {
        terms.filter { $0.enabled }
    }

    /// Generate prompt for Whisper context
    public func generatePrompt() -> String {
        let enabled = enabledTerms.map { $0.term }
        guard !enabled.isEmpty else { return "" }

        // Whisper works best with shorter prompts
        let maxTerms = 50
        let selected = Array(enabled.shuffled().prefix(maxTerms))
        return selected.joined(separator: ", ")
    }

    /// Add a new term
    public func add(_ term: String, category: String) {
        // Avoid duplicates
        guard !terms.contains(where: { $0.term.lowercased() == term.lowercased() }) else { return }
        terms.append(VocabTerm(term: term, category: category))
        save()
    }

    /// Remove a term
    public func remove(_ term: VocabTerm) {
        terms.removeAll { $0.id == term.id }
        save()
    }

    /// Toggle a term's enabled state
    public func toggle(_ term: VocabTerm) {
        if let index = terms.firstIndex(where: { $0.id == term.id }) {
            terms[index].enabled.toggle()
            save()
        }
    }

    /// Enable/disable entire category
    public func setCategory(_ category: String, enabled: Bool) {
        for i in terms.indices where terms[i].category == category {
            terms[i].enabled = enabled
        }
        save()
    }

    /// Reset to default presets
    public func reset() {
        terms.removeAll()
        loadAllPresets()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            terms = try JSONDecoder().decode([VocabTerm].self, from: data)
        } catch {
            print("Failed to load vocabulary: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(terms)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save vocabulary: \(error)")
        }
    }

    // MARK: - Presets

    private func loadAllPresets() {
        loadSoftwareEngineering()
        loadJavaScriptTypeScript()
        loadFrontend()
        loadHipHop()
        loadHoustonTexas()
        loadLouisianaNOLA()
        loadTrackAndField()
        loadBasketball()
        loadSports()
        loadStandUpComedy()
        loadPopCulture()
        loadSouthernSlang()
    }

    private func loadSoftwareEngineering() {
        let terms = [
            // Languages & Runtimes
            "Python", "Rust", "Go", "Golang", "Swift", "Kotlin", "Ruby", "Scala",
            "Haskell", "Elixir", "Clojure", "C++", "C#",

            // Concepts
            "API", "REST", "GraphQL", "gRPC", "WebSocket", "OAuth", "JWT",
            "microservices", "monolith", "serverless", "containerization",
            "Kubernetes", "K8s", "Docker", "CI/CD", "DevOps", "SRE",
            "infrastructure as code", "Terraform", "Ansible", "Pulumi",

            // Databases
            "PostgreSQL", "Postgres", "MySQL", "MongoDB", "Redis", "Cassandra",
            "DynamoDB", "Elasticsearch", "SQLite", "Supabase", "PlanetScale",

            // Cloud
            "AWS", "Azure", "GCP", "Vercel", "Netlify", "Cloudflare", "Heroku",
            "Lambda", "EC2", "S3", "CloudFront", "Route 53",

            // Tools
            "Git", "GitHub", "GitLab", "Bitbucket", "Jira", "Confluence",
            "VS Code", "Vim", "Neovim", "tmux", "zsh", "bash",

            // AI/ML
            "LLM", "GPT", "Claude", "Anthropic", "OpenAI", "Gemini", "Llama",
            "embeddings", "vector database", "RAG", "fine-tuning", "prompt engineering",
            "Langchain", "LlamaIndex", "Pinecone", "Weaviate", "ChromaDB",
            "transformer", "BERT", "diffusion", "Stable Diffusion", "Midjourney",
        ]
        for term in terms {
            add(term, category: "Software Engineering")
        }
    }

    private func loadJavaScriptTypeScript() {
        let terms = [
            // Core
            "JavaScript", "TypeScript", "ECMAScript", "ES6", "ESM", "CommonJS",
            "Node.js", "Node", "Deno", "Bun", "npm", "yarn", "pnpm",

            // Frameworks
            "React", "Vue", "Angular", "Svelte", "SolidJS", "Preact", "Qwik",
            "Next.js", "Nuxt", "Remix", "Astro", "Gatsby", "SvelteKit",

            // State
            "Redux", "Zustand", "Jotai", "Recoil", "MobX", "XState", "TanStack Query",
            "React Query", "SWR", "Apollo Client",

            // Testing
            "Jest", "Vitest", "Mocha", "Chai", "Cypress", "Playwright", "Puppeteer",
            "Testing Library", "React Testing Library", "Storybook",

            // Build
            "Webpack", "Vite", "Rollup", "esbuild", "SWC", "Babel", "Turbopack",
            "tsconfig", "ESLint", "Prettier", "Biome",

            // Types
            "Zod", "Yup", "io-ts", "TypeBox", "tRPC", "Prisma", "Drizzle",
        ]
        for term in terms {
            add(term, category: "JavaScript/TypeScript")
        }
    }

    private func loadFrontend() {
        let terms = [
            // CSS
            "Tailwind", "Tailwind CSS", "CSS-in-JS", "styled-components", "Emotion",
            "Sass", "SCSS", "Less", "PostCSS", "CSS Modules", "UnoCSS",

            // UI Libraries
            "Shadcn", "shadcn/ui", "Radix", "Headless UI", "Chakra UI", "Mantine",
            "Material UI", "MUI", "Ant Design", "DaisyUI", "Flowbite",

            // Animation
            "Framer Motion", "GSAP", "Lottie", "React Spring", "Auto Animate",

            // Concepts
            "SSR", "SSG", "ISR", "hydration", "client-side rendering",
            "server components", "React Server Components", "RSC",
            "virtual DOM", "reconciliation", "memoization", "code splitting",
            "lazy loading", "tree shaking", "bundle size",

            // A11y
            "accessibility", "a11y", "ARIA", "screen reader", "WCAG",
            "semantic HTML", "focus management", "keyboard navigation",
        ]
        for term in terms {
            add(term, category: "Frontend")
        }
    }

    private func loadHipHop() {
        let terms = [
            // Houston/Texas Artists
            "DJ Screw", "Scarface", "Geto Boys", "UGK", "Bun B", "Pimp C",
            "Z-Ro", "Trae tha Truth", "Slim Thug", "Paul Wall", "Mike Jones",
            "Chamillionaire", "Lil Flip", "Lil Keke", "Big Moe", "Fat Pat",
            "Travis Scott", "Megan Thee Stallion", "Don Toliver", "Maxo Kream",

            // Louisiana Artists
            "Lil Wayne", "Juvenile", "BG", "Hot Boys", "Cash Money", "Mannie Fresh",
            "Master P", "No Limit", "Mystikal", "Boosie", "Webbie", "Kevin Gates",
            "NBA YoungBoy", "YoungBoy Never Broke Again",

            // Other Southern
            "OutKast", "Andre 3000", "Big Boi", "T.I.", "Jeezy", "Gucci Mane",
            "Future", "Young Thug", "21 Savage", "2 Chainz", "Ludacris", "Killer Mike",

            // Classic East/West
            "Jay-Z", "Nas", "Biggie", "Tupac", "2Pac", "Wu-Tang", "Rakim",
            "Dr. Dre", "Snoop Dogg", "Ice Cube", "Kendrick Lamar", "J. Cole",

            // Culture Terms
            "chopped and screwed", "sippin'", "swangin'", "bangin'", "trill",
            "candy paint", "swangas", "elbows", "84s", "vogues", "slab",
            "throwed", "codeine", "purple drank", "lean", "syrup",
            "H-Town", "Screwston", "Third Coast", "Dirty South",
            "trap", "crunk", "bounce", "snap music", "drill",

            // Slang
            "bars", "flow", "spit", "cypher", "freestyle", "mixtape",
            "feature", "collab", "diss track", "beef", "clout",
            "drip", "flex", "ice", "bling", "chain", "grill",
        ]
        for term in terms {
            add(term, category: "Hip-Hop")
        }
    }

    private func loadHoustonTexas() {
        let terms = [
            // Houston Areas
            "Third Ward", "Fifth Ward", "Fourth Ward", "Sunnyside", "Acres Homes",
            "South Park", "Hiram Clarke", "Alief", "Sharpstown", "Gulfton",
            "Montrose", "The Heights", "Midtown", "Downtown", "Galleria",
            "Memorial", "Katy", "Sugar Land", "Pearland", "Cypress",
            "Spring", "The Woodlands", "Humble", "Pasadena", "Clear Lake",

            // Texas Cities
            "Dallas", "San Antonio", "Austin", "Fort Worth", "El Paso",
            "Corpus Christi", "Galveston", "Beaumont", "Port Arthur",

            // Houston Landmarks
            "Astrodome", "NRG Stadium", "Toyota Center", "Minute Maid Park",
            "The Galleria", "NASA", "Johnson Space Center", "Ship Channel",
            "Buffalo Bayou", "Hermann Park", "Discovery Green",

            // Culture
            "HTX", "H-Town", "Screwston", "Clutch City", "Space City",
            "Bayou City", "Crush City", "Hustle Town",
            "Rodeo Houston", "Art Car Parade", "Juneteenth",

            // Food
            "kolaches", "Whataburger", "Shipley's", "Frenchy's",
            "Pappadeaux", "Pappasito's", "Goode Company", "Killen's",
            "crawfish boil", "boudin", "brisket", "Texas BBQ",

            // Teams
            "Texans", "Rockets", "Astros", "Dynamo", "Dash",
            "Cougars", "UH", "Rice Owls", "TSU Tigers",
        ]
        for term in terms {
            add(term, category: "Houston/Texas")
        }
    }

    private func loadLouisianaNOLA() {
        let terms = [
            // New Orleans Areas
            "French Quarter", "Garden District", "Treme", "Marigny",
            "Bywater", "Uptown", "Mid-City", "Gentilly", "Lakeview",
            "Ninth Ward", "Lower Ninth Ward", "Holy Cross", "Algiers",
            "Central City", "Irish Channel", "Frenchmen Street", "Magazine Street",

            // Louisiana Cities
            "Baton Rouge", "Lafayette", "Shreveport", "Lake Charles",
            "Monroe", "Alexandria", "Houma", "New Iberia",

            // Culture
            "NOLA", "The Big Easy", "Crescent City", "The Boot",
            "Mardi Gras", "Jazz Fest", "Essence Festival", "Voodoo Fest",
            "second line", "brass band", "jazz funeral", "krewe",
            "Zulu", "Rex", "Endymion", "Bacchus",

            // Food
            "gumbo", "jambalaya", "étouffée", "po'boy", "muffuletta",
            "beignets", "Cafe Du Monde", "crawfish", "boudin",
            "red beans and rice", "dirty rice", "pralines", "king cake",
            "andouille", "tasso", "remoulade", "hot sauce",

            // Slang
            "Where y'at", "Who dat", "lagniappe", "cher", "beb",
            "neutral ground", "making groceries", "dressed", "geaux",
            "bayou", "parish", "levee", "shotgun house",

            // Music
            "jazz", "zydeco", "Cajun music", "bounce", "brass band",
            "Louis Armstrong", "Fats Domino", "Professor Longhair",
            "The Meters", "Rebirth Brass Band", "Big Freedia",
        ]
        for term in terms {
            add(term, category: "Louisiana/NOLA")
        }
    }

    private func loadTrackAndField() {
        let terms = [
            // Events
            "100 meters", "200 meters", "400 meters", "800 meters", "1500 meters",
            "mile", "5K", "10K", "marathon", "half marathon",
            "110 hurdles", "400 hurdles", "3000 steeplechase",
            "4x100", "4x400", "relay", "anchor leg", "exchange zone",
            "high jump", "long jump", "triple jump", "pole vault",
            "shot put", "discus", "javelin", "hammer throw",
            "decathlon", "heptathlon", "pentathlon",

            // Athletes (Sprints)
            "Usain Bolt", "Carl Lewis", "Michael Johnson", "Tyson Gay",
            "Justin Gatlin", "Yohan Blake", "Asafa Powell", "Noah Lyles",
            "Florence Griffith Joyner", "Flo-Jo", "Marion Jones",
            "Sha'Carri Richardson", "Shelly-Ann Fraser-Pryce",

            // Athletes (Distance)
            "Eliud Kipchoge", "Mo Farah", "Haile Gebrselassie", "Kenenisa Bekele",
            "Sifan Hassan", "Faith Kipyegon", "Jakob Ingebrigtsen",

            // Athletes (Field)
            "Mike Powell", "Bob Beamon", "Jackie Joyner-Kersee",
            "Mondo Duplantis", "Renaud Lavillenie",

            // Terms
            "PR", "personal record", "PB", "personal best", "season best",
            "false start", "blocks", "starting blocks", "lane",
            "split", "negative split", "kick", "finishing kick",
            "heat", "semifinal", "final", "Diamond League",
            "Olympic Trials", "World Championships", "NCAA",
        ]
        for term in terms {
            add(term, category: "Track & Field")
        }
    }

    private func loadBasketball() {
        let terms = [
            // Houston
            "Houston Rockets", "Hakeem Olajuwon", "Clyde Drexler",
            "Yao Ming", "Tracy McGrady", "James Harden", "Chris Paul",
            "Rudy Tomjanovich", "Calvin Murphy", "Elvin Hayes",
            "Jalen Green", "Alperen Sengun", "Ime Udoka",

            // Legends
            "Michael Jordan", "LeBron James", "Kobe Bryant", "Magic Johnson",
            "Larry Bird", "Shaq", "Shaquille O'Neal", "Tim Duncan",
            "Kareem Abdul-Jabbar", "Bill Russell", "Wilt Chamberlain",
            "Kevin Durant", "Stephen Curry", "Giannis Antetokounmpo",

            // Current Stars
            "Jayson Tatum", "Luka Doncic", "Joel Embiid", "Nikola Jokic",
            "Anthony Edwards", "Shai Gilgeous-Alexander", "Ja Morant",
            "Victor Wembanyama", "Chet Holmgren",

            // Terms
            "triple-double", "double-double", "and-one", "alley-oop",
            "posterized", "ankle breaker", "crossover", "euro step",
            "step-back", "floater", "fadeaway", "turnaround",
            "pick and roll", "pick and pop", "iso", "isolation",
            "fast break", "transition", "half-court",
            "three-pointer", "downtown", "logo shot", "from deep",
            "paint", "post up", "box out", "rebound", "board",
            "swish", "brick", "airball", "clank",

            // Positions
            "point guard", "shooting guard", "small forward",
            "power forward", "center", "stretch five", "positionless",
        ]
        for term in terms {
            add(term, category: "Basketball")
        }
    }

    private func loadSports() {
        let terms = [
            // Football (Houston focus)
            "Texans", "JJ Watt", "Andre Johnson", "Arian Foster",
            "DeAndre Hopkins", "DeShaun Watson", "CJ Stroud", "Tank Dell",
            "Nico Collins", "Will Anderson Jr", "DeMeco Ryans",

            // NFL General
            "Super Bowl", "touchdown", "interception", "sack",
            "first down", "red zone", "two-minute drill",
            "Hail Mary", "quarterback", "running back", "wide receiver",

            // Baseball (Astros)
            "Astros", "Jose Altuve", "Alex Bregman", "Yordan Alvarez",
            "Kyle Tucker", "Framber Valdez", "Justin Verlander",
            "George Springer", "Carlos Correa", "Dusty Baker",
            "World Series", "home run", "no-hitter", "grand slam",

            // Soccer
            "Dynamo", "Houston Dash", "MLS", "NWSL",
            "goal", "assist", "clean sheet", "penalty kick",

            // Boxing
            "knockout", "TKO", "decision", "split decision",
            "heavyweight", "pound for pound", "title fight",
            "Floyd Mayweather", "Sugar Ray Leonard", "Muhammad Ali",
            "Mike Tyson", "Canelo Alvarez", "Terence Crawford",

            // MMA
            "UFC", "submission", "ground and pound", "takedown",
            "knockout", "rear naked choke", "armbar", "kimura",

            // Golf
            "PGA", "Masters", "birdie", "eagle", "bogey",
            "Tiger Woods", "Jack Nicklaus", "Arnold Palmer",

            // Tennis
            "Grand Slam", "Wimbledon", "US Open", "French Open",
            "Serena Williams", "Venus Williams", "Roger Federer",
        ]
        for term in terms {
            add(term, category: "Sports")
        }
    }

    private func loadStandUpComedy() {
        let terms = [
            // Black Comedians (Classic)
            "Richard Pryor", "Eddie Murphy", "Martin Lawrence",
            "Bernie Mac", "Cedric the Entertainer", "Steve Harvey",
            "DL Hughley", "The Kings of Comedy", "Def Comedy Jam",
            "Robin Harris", "Redd Foxx", "Flip Wilson", "Bill Cosby",

            // 90s-2000s Era
            "Chris Rock", "Dave Chappelle", "Chris Tucker",
            "Jamie Foxx", "Kevin Hart", "Katt Williams",
            "Mike Epps", "Sommore", "Mo'Nique", "Earthquake",
            "Bruce Bruce", "Lavell Crawford", "Rickey Smiley",

            // Modern Era
            "Roy Wood Jr", "Hannibal Buress", "Jerrod Carmichael",
            "Lil Rel Howery", "Tiffany Haddish", "Leslie Jones",
            "Wanda Sykes", "Amanda Seales", "Lil Duval",

            // Other Legends
            "George Carlin", "Jerry Seinfeld", "Bill Burr",
            "Louis CK", "Jim Gaffigan", "Mitch Hedberg",
            "Patrice O'Neal", "Greg Giraldo", "Norm Macdonald",

            // Shows & Terms
            "Chappelle's Show", "Saturday Night Live", "SNL",
            "In Living Color", "Wild 'n Out", "Comic View",
            "set", "bit", "punchline", "callback", "crowd work",
            "roast", "heckler", "bombing", "killing it",

            // Famous Bits
            "Rick James", "I'm Rick James, bitch", "Charlie Murphy",
            "True Hollywood Stories", "Player Haters Ball",
            "Raw", "Delirious", "The Original Kings of Comedy",
            "Bring the Pain", "Bigger & Blacker", "Kill the Messenger",
        ]
        for term in terms {
            add(term, category: "Stand-Up Comedy")
        }
    }

    private func loadPopCulture() {
        let terms = [
            // 80s
            "MTV", "VHS", "Walkman", "boombox", "breakdancing",
            "Michael Jackson", "Prince", "Madonna", "Run-DMC",
            "Transformers", "GI Joe", "He-Man", "Thundercats",
            "The Cosby Show", "A Different World", "Fresh Prince",

            // 90s
            "Nickelodeon", "Cartoon Network", "BET", "TRL",
            "Aaliyah", "TLC", "Destiny's Child", "Brandy",
            "Martin", "Living Single", "Moesha", "The Parkers",
            "Boyz n the Hood", "Menace II Society", "Friday",
            "Space Jam", "House Party", "New Jack City",

            // 2000s
            "MySpace", "AIM", "away message", "ringtones",
            "Beyoncé", "Rihanna", "Kanye West", "T-Pain",
            "The Wire", "The Game", "Girlfriends",

            // 2010s-2020s
            "Instagram", "TikTok", "Twitter", "X", "Vine",
            "streaming", "Netflix", "Hulu", "HBO Max",
            "Drake", "Cardi B", "Lizzo", "Doja Cat",
            "Atlanta", "Insecure", "Abbott Elementary",
            "Black Panther", "Get Out", "Us", "Nope",

            // Memes & Phrases
            "no cap", "on God", "period", "slay", "ate",
            "understood the assignment", "that's cap", "sus",
            "vibe check", "it's giving", "main character energy",
            "rent free", "living rent free", "touch grass",
            "ratio", "L take", "W", "based", "goated",
        ]
        for term in terms {
            add(term, category: "Pop Culture")
        }
    }

    private func loadSouthernSlang() {
        let terms = [
            // General Southern
            "y'all", "fixin' to", "might could", "used to could",
            "over yonder", "cattywampus", "hunky-dory", "tump over",
            "carry", "cut off the lights", "mash", "buggy",
            "coke", "sweet tea", "bless your heart",

            // AAVE / Black Southern
            "ain't", "finna", "tryna", "boutta", "ion",
            "bussin'", "trippin'", "cappin'", "slidin'",
            "bet", "say less", "facts", "no doubt",
            "fam", "bruh", "sis", "cuz", "bro",
            "pressed", "salty", "tight", "heated",
            "lowkey", "highkey", "deadass", "straight up",
            "that's crazy", "on me", "on my mama",
            "fasho", "fo' sho", "for real", "fr fr",

            // Texas Specific
            "fixin'", "all y'all", "come to find out",
            "hotter than fish grease", "madder than a wet hen",
            "rode hard and put up wet", "all hat no cattle",
            "big as Dallas", "come hell or high water",

            // Houston Specific
            "trill", "throwed", "swangin'", "bangin'",
            "grippin' grain", "sittin' sideways", "tippin'",
            "comin' down", "pourin' up", "leanin'",
        ]
        for term in terms {
            add(term, category: "Southern Slang")
        }
    }
}
