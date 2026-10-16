//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// The featured collections calendar.
//
// Keyword ids were looked up with TMDB's /search/keyword and checked with /keyword/{id}; every shelf's
// query was run against /discover/movie and /discover/tv and kept only when it returned relevant,
// well-known titles (TV is left out where it didn't, e.g. Easter, New Year, Towel Day). Genre ids are
// TMDB's (TV horror is keyword 315058, as in the Categories catalog). Pins are TMDB keys checked with
// /search. Backdrops are textless (no-language) art from each collection's anchor or top result.
// Dropped for weak results: Bigfoot/cryptid weekend (no fixed date, thin TV), Mole Day, Bloomsday.

extension FeaturedCollection {

    static let calendar: [FeaturedCollection] = [
        FeaturedCollection(
            id: "latin-heritage",
            title: "Latin American Heritage Month",
            tagline: "Films and series from across Latin America, plus Latino stories from the US",
            tier: .major,
            rule: .range(from: .init(9, 15), through: .init(10, 15)),
            priority: 70,
            backdropPath: "/c4U96GrPRfnNrS01mBtqnocvlLJ.jpg",
            shelves: [
                .init(
                    id: "latin-america",
                    title: "Latin America",
                    parts: [.init(
                        movie: .init(
                            countries: ["MX", "AR", "BR", "CO", "CL", "PE", "CU", "VE", "UY", "PR", "DO", "GT", "BO", "EC"],
                            minVotes: 100
                        ),
                        tv: .init(
                            withoutGenres: [10763, 10764, 10767],
                            countries: ["MX", "AR", "BR", "CO", "CL", "PE", "CU", "VE", "UY", "PR", "DO", "GT", "BO", "EC"],
                            minVotes: 50
                        )
                    )]
                ),
                .init(
                    id: "latino-stories",
                    title: "Latino Stories",
                    parts: [.init(
                        movie: .init(keywords: [255_632, 164_253, 41334, 272_164, 253_865]),
                        tv: .init(keywords: [255_632, 164_253, 41334, 272_164, 253_865])
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "fall",
            title: "Fall Favorites",
            tagline: "Cozy mysteries, small towns and harvest-season comfort",
            tier: .major,
            rule: .range(from: .init(9, 22), through: .init(11, 20)),
            priority: 50,
            backdropPath: "/8U2ndZrneigI2zkvGuTJtt1ZsxK.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Fall Favorites",
                    parts: [.init(
                        movie: .init(keywords: [178_883, 1735, 231_596, 12570, 207_046, 1415, 190_061], withoutGenres: [27]),
                        tv: .init(keywords: [178_883, 1735, 231_596, 12570, 207_046, 1415, 190_061], withoutKeywords: [315_058])
                    )]
                ),
            ],
            pins: ["tv-4586"]
        ),
        FeaturedCollection(
            id: "halloween",
            title: "Halloween",
            tagline: "Spooky fun for everyone, with a scarier shelf after dark",
            tier: .major,
            rule: .range(from: .init(10, 1), through: .init(10, 31)),
            priority: 90,
            backdropPath: "/dSfrsjhqC6lYe7LYDYnzWeXZmEl.jpg",
            shelves: [
                .init(
                    id: "spooky-fun",
                    title: "Spooky Fun",
                    parts: [.init(
                        movie: .init(keywords: [3335, 180_193, 229_717, 9694], withoutGenres: [27]),
                        tv: .init(keywords: [3335, 180_193, 229_717, 9694, 318_653], withoutKeywords: [315_058])
                    )]
                ),
                .init(
                    id: "family",
                    title: "Family & Animated",
                    parts: [
                        .init(movie: .init(keywords: [3335, 180_193, 229_717, 9694]), tv: .init(keywords: [
                            3335,
                            180_193,
                            229_717,
                            9694,
                            318_653
                        ])),
                        .init(movie: .init(genres: [10751, 16]), tv: .init(genres: [10751, 16, 10762]))
                    ]
                ),
                .init(
                    id: "scarier",
                    title: "Scarier",
                    parts: [
                        .init(movie: .init(keywords: [3335, 180_193, 229_717, 9694]), tv: .init(keywords: [
                            3335,
                            180_193,
                            229_717,
                            9694,
                            318_653
                        ])),
                        .init(movie: .init(genres: [27]), tv: .init(keywords: [315_058]))
                    ]
                ),
            ]
        ),
        FeaturedCollection(
            id: "dia-de-muertos",
            title: "Día de los Muertos",
            tagline: "Remembering the ones we love, with marigolds and music",
            tier: .major,
            rule: .range(from: .init(10, 28), through: .init(11, 2)),
            priority: 82,
            backdropPath: "/g7CHF8gTLGooTbP4GznIGwaqAGL.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Día de los Muertos",
                    parts: [.init(movie: .init(keywords: [209_789, 272_687, 248_688, 322_048]), tv: nil)]
                ),
            ],
            pins: ["movie-354912", "movie-228326"]
        ),
        FeaturedCollection(
            id: "native-heritage",
            title: "Native American Heritage Month",
            tagline: "Indigenous creators and stories",
            tier: .major,
            rule: .month(11),
            priority: 70,
            backdropPath: "/4vC3CijGu8g2Z1UobwkJpRQHOVO.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Native American Heritage",
                    parts: [.init(
                        movie: .init(keywords: [10322, 1551, 155_805, 253_307, 215_162, 184_984]),
                        tv: .init(keywords: [10322, 1551, 155_805, 253_307, 215_162, 184_984], minVotes: 15)
                    )]
                ),
            ],
            pins: ["tv-95215", "tv-93748", "tv-128904"]
        ),
        FeaturedCollection(
            id: "thanksgiving",
            title: "Thanksgiving",
            tagline: "Family gatherings, travel chaos and a lot of food",
            tier: .major,
            rule: .weekday(4, .thursday, month: 11),
            lead: 5,
            trail: 3,
            priority: 92,
            backdropPath: "/4f8JBqvWyPObKTrjvJnp9BeOUyY.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Thanksgiving",
                    parts: [.init(
                        movie: .init(keywords: [4543, 374_738], withoutGenres: [27]),
                        tv: .init(keywords: [1918, 222_083, 240_810, 227_635])
                    )]
                ),
            ],
            pins: ["movie-2609", "movie-13479"]
        ),
        FeaturedCollection(
            id: "holiday-season",
            title: "Holiday Season",
            tagline: "Christmas classics, Hanukkah and holiday specials",
            tier: .major,
            rule: .range(from: .init(11, 25), through: .init(12, 31)),
            priority: 85,
            backdropPath: "/5nhp41gx49vXjwXuDXJwQrRFsng.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Holiday Season",
                    parts: [.init(
                        movie: .init(keywords: [207_317, 7328, 272_884, 189_966, 273_278, 255_088], withoutGenres: [27]),
                        tv: .init(keywords: [207_317, 7328, 272_884, 189_966, 273_278, 255_088], withoutGenres: [16], minVotes: 25)
                    )]
                ),
            ],
            pins: ["movie-10719", "movie-771"]
        ),
        FeaturedCollection(
            id: "new-year",
            title: "New Year, Fresh Start",
            tagline: "Midnight countdowns and second chances",
            tier: .major,
            rule: .range(from: .init(12, 26), through: .init(1, 7)),
            priority: 87,
            backdropPath: "/66Kn4XWhkuPkJxOJyPEx4U2CUfN.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "New Year",
                    parts: [.init(movie: .init(keywords: [613, 5632, 171_845, 318_862, 252_123], withoutGenres: [27]), tv: nil)]
                ),
            ]
        ),
        FeaturedCollection(
            id: "lunar-new-year",
            title: "Lunar New Year",
            tagline: "Chinese, Korean and Vietnamese film and TV",
            tier: .major,
            rule: .table(.lunarNewYear),
            lead: 7,
            trail: 7,
            priority: 80,
            backdropPath: "/pGxUbJ1vKuMYeEjKDokFI7DNbSG.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Lunar New Year",
                    parts: [.init(
                        movie: .init(countries: ["CN", "KR", "VN", "TW", "HK"], minVotes: 150),
                        tv: .init(withoutGenres: [10763, 10764, 10767], countries: ["CN", "KR", "VN", "TW", "HK"], minVotes: 80)
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "black-history",
            title: "Black History Month",
            tagline: "Black stories, history makers and civil rights",
            tier: .major,
            rule: .month(2),
            priority: 70,
            backdropPath: "/rfkIeCaIHhN3K5wjJJqKmfUjYp8.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Black History Month",
                    parts: [.init(
                        movie: .init(keywords: [190_675, 256_015, 4098, 270_891, 251_436, 339_021]),
                        tv: .init(keywords: [190_675, 256_015, 4098, 270_891, 251_436, 339_021], minVotes: 20)
                    )]
                ),
            ],
            pins: ["movie-381284"]
        ),
        FeaturedCollection(
            id: "valentines",
            title: "Valentine's Day",
            tagline: "Rom-coms to fall for",
            tier: .major,
            rule: .range(from: .init(2, 7), through: .init(2, 14)),
            priority: 80,
            backdropPath: "/o7Oy9Gbx1CCyaweL8xUhtMW4Puq.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Rom-Coms",
                    parts: [.init(
                        movie: .init(genres: [10749], keywords: [9799]),
                        tv: .init(keywords: [9799], withoutGenres: [16], minVotes: 50)
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "womens-history",
            title: "Women's History Month",
            tagline: "Stories of women who changed the world",
            tier: .major,
            rule: .month(3),
            priority: 70,
            backdropPath: "/lqxxwTRk0l7CubY6JkJdhnwJEkn.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Women's History Month",
                    parts: [.init(
                        movie: .init(keywords: [2383, 212_915, 191_731, 11718, 275_739, 340_876], minVotes: 800),
                        tv: .init(keywords: [2383, 212_915, 191_731, 11718, 275_739, 340_876], minVotes: 80)
                    )]
                ),
            ],
            pins: ["movie-331482"]
        ),
        FeaturedCollection(
            id: "st-patricks",
            title: "St. Patrick's Day",
            tagline: "Irish film and TV",
            tier: .major,
            rule: .range(from: .init(3, 10), through: .init(3, 17)),
            priority: 75,
            backdropPath: "/nQyQ4c8DUvXra1LDWnNfV9QJluD.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Irish Film & TV",
                    parts: [.init(
                        movie: .init(keywords: [14985, 299_594, 209_352, 4729, 232_529]),
                        tv: .init(keywords: [14985, 299_594, 209_352, 4729, 232_529])
                    )]
                ),
            ],
            pins: ["tv-76148", "movie-674324"]
        ),
        FeaturedCollection(
            id: "easter",
            title: "Easter & Spring",
            tagline: "Springtime stories for the whole family",
            tier: .major,
            rule: .easter,
            lead: 13,
            trail: 1,
            priority: 80,
            backdropPath: "/46IGtYNjpIvQYRIQlb2X493Wh8x.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Easter & Spring",
                    parts: [.init(movie: .init(keywords: [9921, 9923, 350_569, 233_042, 6202, 270_374]), tv: nil)]
                ),
            ]
        ),
        FeaturedCollection(
            id: "earth-day",
            title: "Earth Day",
            tagline: "Nature documentaries and our changing planet",
            tier: .major,
            rule: .range(from: .init(4, 15), through: .init(4, 22)),
            priority: 72,
            backdropPath: "/qmRUwosX4BsCj6QanpBYScLl3Sp.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Earth Day",
                    parts: [.init(
                        movie: .init(genres: [99], keywords: [221_355, 9902, 2210, 33577, 18330, 343_739]),
                        tv: .init(genres: [99], keywords: [221_355, 9902, 2210, 33577, 18330, 343_739], minVotes: 20)
                    )]
                ),
            ],
            pins: ["tv-1044", "tv-83880"]
        ),
        FeaturedCollection(
            id: "aapi-heritage",
            title: "AAPI Heritage Month",
            tagline: "Asian American and Pacific Islander stories",
            tier: .major,
            rule: .month(5),
            priority: 70,
            backdropPath: "/fIwiFha3WPu5nHkBeMQ4GzEk0Hv.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "AAPI Heritage Month",
                    parts: [.init(
                        movie: .init(keywords: [280_028, 179_485, 231_519, 181_089, 171_584, 303_829]),
                        tv: .init(keywords: [280_028, 179_485, 231_519, 181_089, 171_584, 303_829])
                    )]
                ),
            ],
            pins: ["movie-545611", "movie-455207"]
        ),
        FeaturedCollection(
            id: "pride",
            title: "Pride Month",
            tagline: "LGBTQ+ stories, joyful and groundbreaking",
            tier: .major,
            rule: .month(6),
            priority: 70,
            backdropPath: "/8FCHJ21JBQOgATY2WI8vwYAiXg8.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Pride Month",
                    parts: [.init(
                        movie: .init(keywords: [158_718, 363_345, 264_386, 173_662, 183_440, 280_179]),
                        tv: .init(keywords: [158_718, 363_345, 264_386, 173_662, 183_440, 280_179])
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "juneteenth",
            title: "Juneteenth",
            tagline: "Freedom, history and the fight for civil rights",
            tier: .major,
            rule: .range(from: .init(6, 12), through: .init(6, 19)),
            priority: 78,
            backdropPath: "/n0uefHZH2sX0HxU5Ec1w1tF8n3k.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Juneteenth",
                    parts: [.init(
                        movie: .init(keywords: [298_310, 190_675, 256_015, 4098, 270_891, 251_436, 339_021]),
                        tv: .init(keywords: [298_310, 190_675, 256_015, 4098, 270_891, 251_436, 339_021], minVotes: 20)
                    )]
                ),
            ],
            pins: ["movie-653668"]
        ),
        FeaturedCollection(
            id: "summer-kickoff",
            title: "Summer Kickoff",
            tagline: "Beach days, summer camp and long nights",
            tier: .major,
            rule: .weekday(-1, .monday, month: 5),
            lead: 2,
            trail: 30,
            priority: 55,
            backdropPath: "/4Xh2a1WeTp6b8Ksvug0pAMbX3dT.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Summer Kickoff",
                    parts: [.init(
                        movie: .init(keywords: [13088, 14714, 200_129, 213_450, 281_794, 966], withoutGenres: [27]),
                        tv: .init(
                            keywords: [13088, 14714, 200_129, 213_450, 281_794, 966],
                            withoutGenres: [10764],
                            withoutKeywords: [315_058]
                        )
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "fourth-of-july",
            title: "Fourth of July",
            tagline: "Americana, fireworks and summer blockbusters",
            tier: .major,
            rule: .range(from: .init(6, 28), through: .init(7, 4)),
            priority: 85,
            backdropPath: "/neeNHeXjMF5fXoCJRsOmkNGC7q.jpg",
            shelves: [
                .init(id: "americana", title: "Americana", parts: [.init(movie: .init(keywords: [159_743, 235_503, 1627]), tv: nil)]),
                .init(id: "blockbusters", title: "Blockbusters", parts: [.init(movie: .init(genres: [28, 12], minVotes: 8000), tv: nil)]),
            ]
        ),
        FeaturedCollection(
            id: "back-to-school",
            title: "Back to School",
            tagline: "Classrooms, campuses and coming of age",
            tier: .major,
            rule: .range(from: .init(8, 15), through: .init(9, 10)),
            priority: 55,
            backdropPath: "/wvXxKpFGXvQJRB0nvvfURhRD3C0.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Back to School",
                    parts: [.init(
                        movie: .init(keywords: [187_282, 6270, 3616, 10508], withoutGenres: [27]),
                        tv: .init(keywords: [187_282, 6270, 3616, 10508], withoutGenres: [16], withoutKeywords: [315_058])
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "oscars",
            title: "Oscars Season",
            tagline: "Best Picture winners and acclaimed dramas",
            tier: .major,
            rule: .table(.oscars),
            lead: 24,
            trail: 1,
            priority: 68,
            backdropPath: "/off0xgvtfHY82l3MC4mDpCk1APY.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Oscars Season",
                    parts: [.init(movie: .init(genres: [18], minRating: 7.6, minVotes: 3000), tv: nil)]
                ),
            ],
            pins: [
                "movie-12162",
                "movie-45269",
                "movie-74643",
                "movie-68734",
                "movie-76203",
                "movie-194662",
                "movie-314365",
                "movie-376867",
                "movie-399055",
                "movie-490132",
                "movie-496243",
                "movie-581734",
                "movie-776503",
                "movie-545611",
                "movie-872585",
                "movie-1064213"
            ]
        ),
        FeaturedCollection(
            id: "emmys",
            title: "Emmys Season",
            tagline: "Award-winning dramas and comedies",
            tier: .major,
            rule: .table(.emmys),
            lead: 14,
            trail: 1,
            priority: 65,
            backdropPath: "/z3BkMbCy5ajZPMyKEUwsPHuz2cV.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Emmys Season",
                    parts: [.init(
                        movie: nil,
                        tv: .init(genres: [18, 35], withoutGenres: [16, 10762, 10764], years: 2008 ... 2099, minRating: 8.0, minVotes: 500)
                    )]
                ),
            ],
            pins: [
                "tv-250307",
                "tv-126308",
                "tv-76331",
                "tv-65494",
                "tv-1399",
                "tv-1396",
                "tv-1104",
                "tv-136315",
                "tv-247767",
                "tv-124101",
                "tv-97546",
                "tv-61662",
                "tv-67070",
                "tv-2947",
                "tv-70796"
            ]
        ),
        FeaturedCollection(
            id: "diwali",
            title: "Diwali",
            tagline: "Indian film and TV for the festival of lights",
            tier: .major,
            rule: .table(.diwali),
            lead: 4,
            trail: 2,
            priority: 78,
            backdropPath: "/i0Y0wP8H6SRgjr6QmuwbtQbS24D.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Diwali",
                    parts: [.init(
                        movie: .init(countries: ["IN"], minVotes: 100),
                        tv: .init(withoutGenres: [10763, 10764, 10767], countries: ["IN"], minVotes: 60)
                    )]
                ),
            ],
            pins: ["movie-579974"]
        ),
        FeaturedCollection(
            id: "groundhog-day",
            title: "Stuck in a Loop",
            tagline: "Groundhog Day: time loops, again and again",
            tier: .fun,
            rule: .day(.init(2, 2)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/4W6RYDNe4OByNryOCvJprrutm9h.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Time Loops",
                    parts: [.init(movie: .init(keywords: [10854, 366_519, 364_334]), tv: .init(keywords: [10854, 366_519, 364_334]))]
                ),
            ],
            pins: ["movie-137", "movie-587792"]
        ),
        FeaturedCollection(
            id: "galentines",
            title: "Galentine's Day",
            tagline: "Friendship comedies for your best friends",
            tier: .fun,
            rule: .day(.init(2, 13)),
            lead: 3,
            priority: 45,
            backdropPath: "/v7FPlZuuwJZ6YwJggf3Jx5pZNAz.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Friendship Comedies",
                    parts: [.init(
                        movie: .init(genres: [35], keywords: [5248, 356_269]),
                        tv: .init(genres: [35], keywords: [5248, 356_269])
                    )]
                ),
            ],
            pins: ["tv-8592"]
        ),
        FeaturedCollection(
            id: "pizza-day",
            title: "National Pizza Day",
            tagline: "Food films and food shows",
            tier: .fun,
            rule: .day(.init(2, 9)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/zeoaHdXRDd5IoUiMVsNhwTZm78B.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Food Films & Shows",
                    parts: [.init(
                        movie: .init(keywords: [1918, 222_083, 240_810, 227_635, 4735, 18293]),
                        tv: .init(keywords: [1918, 222_083, 240_810, 227_635, 4735, 18293])
                    )]
                ),
            ],
            pins: ["movie-2062", "tv-136315"]
        ),
        FeaturedCollection(
            id: "leap-day",
            title: "Leap Day",
            tagline: "An extra day for time oddities",
            tier: .fun,
            rule: .leapDay,
            lead: 3,
            trail: 1,
            priority: 42,
            backdropPath: "/b9q9VmbXDvJmTziRqkwdEmFdwhr.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Time Oddities",
                    parts: [.init(
                        movie: .init(keywords: [191_886, 310_751, 10854, 5455, 4379]),
                        tv: .init(keywords: [191_886, 310_751, 10854, 5455, 4379])
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "pi-day",
            title: "Pi Day",
            tagline: "Math, science and genius stories",
            tier: .fun,
            rule: .day(.init(3, 14)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/xj1Sv1xm4Y0ydBueGuf10Y9qM0O.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Math & Genius",
                    parts: [.init(
                        movie: .init(keywords: [6009, 2303, 230_113, 14518]),
                        tv: .init(keywords: [6009, 2303, 230_113, 14518, 6257, 14760])
                    )]
                ),
            ],
            pins: ["movie-489"]
        ),
        FeaturedCollection(
            id: "friday-13th",
            title: "Friday the 13th",
            tagline: "Slashers, curses and very bad luck",
            tier: .fun,
            rule: .fridayThe13th,
            lead: 2,
            priority: 35,
            backdropPath: "/xWBiXclrRmTggQHMRsIn84YHavs.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Slashers & Bad Luck",
                    parts: [.init(movie: .init(keywords: [12339, 4671, 6156]), tv: .init(keywords: [12339, 4671, 6156]))]
                ),
            ]
        ),
        FeaturedCollection(
            id: "star-wars-day",
            title: "Star Wars Day",
            tagline: "May the Fourth: space opera from galaxies far, far away",
            tier: .fun,
            rule: .day(.init(5, 4)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/zqkmTXzjkAgXmEWLRsY4UpTWCeo.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Space Opera",
                    parts: [.init(movie: .init(keywords: [161_176, 196_483]), tv: .init(keywords: [161_176, 196_483]))]
                ),
            ],
            pins: ["movie-11", "tv-83867", "tv-82856"]
        ),
        FeaturedCollection(
            id: "baking-day",
            title: "World Baking Day",
            tagline: "Baking competitions and kitchen stories",
            tier: .fun,
            rule: .weekday(3, .sunday, month: 5),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/7rB1VhVXtLFTnOCY1Hz7ZEIz7CO.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Baking & Food",
                    parts: [.init(
                        movie: .init(keywords: [182_282, 291_036, 1918]),
                        tv: .init(keywords: [182_282, 240_810, 222_083, 227_635])
                    )]
                ),
            ],
            pins: ["tv-34549", "tv-77791"]
        ),
        FeaturedCollection(
            id: "towel-day",
            title: "Towel Day",
            tagline: "Don't panic: absurd sci-fi comedy",
            tier: .fun,
            rule: .day(.init(5, 25)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/bp2nxKuLqcVmMwa5wTsgO4tYm8p.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Absurd Sci-Fi Comedy",
                    parts: [
                        .init(movie: .init(genres: [878], withoutGenres: [16, 10751]), tv: nil),
                        .init(
                            movie: .init(genres: [35], keywords: [11931, 214_655, 309_974, 384_363, 210_710, 8201, 9755, 376_549, 221_375]),
                            tv: nil
                        )
                    ]
                ),
            ],
            pins: ["movie-7453", "movie-926", "movie-957"]
        ),
        FeaturedCollection(
            id: "dinosaur-day",
            title: "Dinosaur Day",
            tagline: "Dinosaurs, from Jurassic to cartoon",
            tier: .fun,
            rule: .day(.init(6, 1)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/4SyDTF02R5BepqSdQmOaNCHObzF.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Dinosaurs",
                    parts: [.init(movie: .init(keywords: [12616, 381_574]), tv: .init(keywords: [12616, 381_574]))]
                ),
            ],
            pins: ["movie-329"]
        ),
        FeaturedCollection(
            id: "ufo-day",
            title: "World UFO Day",
            tagline: "Close encounters and unexplained lights",
            tier: .fun,
            rule: .day(.init(7, 2)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/yBCekmb7vK70xUhtsRQBcTu65sB.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "UFOs & Aliens",
                    parts: [.init(
                        movie: .init(keywords: [9738, 12553, 223_550, 251_352]),
                        tv: .init(keywords: [9738, 12553, 223_550, 251_352])
                    )]
                ),
            ],
            pins: ["movie-840"]
        ),
        FeaturedCollection(
            id: "moon-landing",
            title: "Moon Landing Day",
            tagline: "Astronauts, the space race and one giant leap",
            tier: .fun,
            rule: .day(.init(7, 20)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/n0FDJI9c0uWiZwm8wgXVjaMBn96.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Astronauts & the Space Race",
                    parts: [.init(
                        movie: .init(keywords: [7422, 226_233, 14626, 156_836, 191_132]),
                        tv: .init(keywords: [7422, 226_233, 14626, 156_836, 191_132])
                    )]
                ),
            ],
            pins: ["movie-568"]
        ),
        FeaturedCollection(
            id: "shark-week",
            title: "Shark Week",
            tagline: "Sharks and the deep blue sea",
            tier: .fun,
            rule: .week(4, .sunday, month: 7),
            priority: 40,
            backdropPath: "/i1yf91svRHX45l9BXL8rVFzLoPH.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Sharks & the Deep Sea",
                    parts: [.init(
                        movie: .init(keywords: [15097, 2988, 158_108, 2769]),
                        tv: .init(keywords: [15097, 2988, 2769], minVotes: 15)
                    )]
                ),
            ],
            pins: ["movie-578"]
        ),
        FeaturedCollection(
            id: "cat-day",
            title: "International Cat Day",
            tagline: "Cats, cartoon and otherwise",
            tier: .fun,
            rule: .day(.init(8, 8)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/pZfpUMEJzw9BZHtXuZzzOrRxtMa.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Cats",
                    parts: [.init(movie: .init(keywords: [977, 188_748, 155_488]), tv: .init(keywords: [977, 188_748, 155_488]))]
                ),
            ],
            pins: ["movie-823219"]
        ),
        FeaturedCollection(
            id: "video-game-day",
            title: "National Video Game Day",
            tagline: "Video game adaptations",
            tier: .fun,
            rule: .day(.init(9, 12)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/lY2DhbA7Hy44fAKddr06UrXWWaQ.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Video Game Adaptations",
                    parts: [.init(movie: .init(keywords: [41645]), tv: .init(keywords: [41645]))]
                ),
            ],
            pins: ["tv-100088"]
        ),
        FeaturedCollection(
            id: "pirate-day",
            title: "Talk Like a Pirate Day",
            tagline: "Pirates and the high seas",
            tier: .fun,
            rule: .day(.init(9, 19)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/qD211Hb5XwFxrszzBBe5EUYJerh.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Pirates & High Seas",
                    parts: [.init(
                        movie: .init(keywords: [12988, 185_200, 291_537, 368_907, 196_483]),
                        tv: .init(keywords: [12988, 185_200, 291_537, 368_907, 196_483])
                    )]
                ),
            ],
            pins: ["tv-111110", "movie-22"]
        ),
        FeaturedCollection(
            id: "hobbit-day",
            title: "Hobbit Day",
            tagline: "Epic fantasy for second breakfast",
            tier: .fun,
            rule: .day(.init(9, 22)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/oiwc338EoBgS4sEI2ixAny4KQKg.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Epic Fantasy",
                    parts: [.init(
                        movie: .init(keywords: [211_227, 375_250, 234_213, 170_362, 12554, 603]),
                        tv: .init(keywords: [211_227, 375_250, 234_213, 170_362, 12554, 603])
                    )]
                ),
            ],
            pins: ["movie-120", "movie-49051"]
        ),
        FeaturedCollection(
            id: "oktoberfest",
            title: "Oktoberfest",
            tagline: "German film and TV",
            tier: .fun,
            rule: .oktoberfest,
            priority: 38,
            backdropPath: "/kgP4YOUWKhJZWL0Z8LJ6G6LBMEM.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "German Film & TV",
                    parts: [.init(
                        movie: .init(languages: ["de"], minVotes: 100),
                        tv: .init(withoutGenres: [10763, 10764, 10766, 10767], languages: ["de"], minVotes: 30)
                    )]
                ),
            ]
        ),
        FeaturedCollection(
            id: "mean-girls-day",
            title: "Mean Girls Day",
            tagline: "On October 3rd, teen comedies",
            tier: .fun,
            rule: .day(.init(10, 3)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/nP3y0TkR6XniFs9J53qQkg4Bnnk.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Teen Comedies",
                    parts: [.init(
                        movie: .init(genres: [35], keywords: [155_722, 6270]),
                        tv: .init(genres: [35], keywords: [155_722, 6270])
                    )]
                ),
            ],
            pins: ["movie-10625"]
        ),
        FeaturedCollection(
            id: "space-week",
            title: "World Space Week",
            tagline: "Space exploration, real and imagined",
            tier: .fun,
            rule: .range(from: .init(10, 4), through: .init(10, 10)),
            priority: 38,
            backdropPath: "/mDfJG3LC3Dqb67AZ52x3Z0jU0uB.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Space",
                    parts: [.init(movie: .init(keywords: [9882, 3801, 14626, 191_132]), tv: .init(keywords: [9882, 3801, 14626, 191_132]))]
                ),
            ]
        ),
        FeaturedCollection(
            id: "back-to-the-future-day",
            title: "Back to the Future Day",
            tagline: "October 21: time travel, Great Scott",
            tier: .fun,
            rule: .day(.init(10, 21)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/5bzPWQ2dFUl2aZKkp7ILJVVkRed.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Time Travel",
                    parts: [.init(movie: .init(keywords: [4379, 5455]), tv: .init(keywords: [4379, 5455]))]
                ),
            ],
            pins: ["movie-105"]
        ),
        FeaturedCollection(
            id: "festivus",
            title: "Festivus",
            tagline: "A sitcom for the rest of us",
            tier: .fun,
            rule: .day(.init(12, 23)),
            lead: 3,
            trail: 1,
            priority: 40,
            backdropPath: "/tMRdEsMg9MyXAkcufK9YJEeIaNW.jpg",
            shelves: [
                .init(
                    id: "main",
                    title: "Sitcoms",
                    parts: [.init(movie: nil, tv: .init(genres: [35], keywords: [193_171], minVotes: 100))]
                ),
            ],
            pins: ["tv-1400", "tv-4608", "tv-18347", "tv-4589"]
        ),
    ]
}
