//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// Category definitions for the Categories tab.
//
// Genre ids come from TMDB's /genre/movie/list and /genre/tv/list. Keyword ids were looked up with
// TMDB's /search/keyword and checked against /discover/movie and /discover/tv (each returns results).
// TV has no Horror, Thriller, Romance or History genre on TMDB, so those use keywords for shows.
// Backdrops are the most popular result of each category's own query (fixed so the landing page
// needs no requests). Streaming service tiles are built at runtime from the user's services.

extension BrowseCategory {

    static let catalog: [BrowseCategory] = [
        BrowseCategory(
            id: "action",
            title: "Action & Adventure",
            group: .genres,
            backdropPath: "/mDfJG3LC3Dqb67AZ52x3Z0jU0uB.jpg",
            movie: .init(genres: [28, 12]),
            tv: .init(genres: [10759])
        ),
        BrowseCategory(
            id: "comedy",
            title: "Comedy",
            group: .genres,
            backdropPath: "/jJKZaTBNenlFclQyjrnvzkRmvWE.jpg",
            movie: .init(genres: [35]),
            tv: .init(genres: [35])
        ),
        BrowseCategory(
            id: "drama",
            title: "Drama",
            group: .genres,
            backdropPath: "/8sNiAPPYU14PUepFNeSNGUTiHW.jpg",
            movie: .init(genres: [18]),
            tv: .init(genres: [18])
        ),
        BrowseCategory(
            id: "crime",
            title: "Crime",
            group: .genres,
            backdropPath: "/9FE5eD92WfVCiivM9Pq9GVSrlWk.jpg",
            movie: .init(genres: [80]),
            tv: .init(genres: [80])
        ),
        BrowseCategory(
            id: "thriller",
            title: "Thriller",
            group: .genres,
            backdropPath: "/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg",
            movie: .init(genres: [53]),
            tv: .init(keywords: [316_362])
        ),
        BrowseCategory(
            id: "mystery",
            title: "Mystery",
            group: .genres,
            backdropPath: "/9P4IIMYY3HifqeruZq0ZZ9g7YUi.jpg",
            movie: .init(genres: [9648]),
            tv: .init(genres: [9648])
        ),
        BrowseCategory(
            id: "scifi",
            title: "Sci-Fi",
            group: .genres,
            backdropPath: "/9BBTo63ANSmhC4e6r62OJFuK2GL.jpg",
            movie: .init(genres: [878]),
            tv: .init(genres: [10765])
        ),
        BrowseCategory(
            id: "fantasy",
            title: "Fantasy",
            group: .genres,
            backdropPath: "/hziiv14OpD73u9gAak4XDDfBKa2.jpg",
            movie: .init(genres: [14]),
            tv: .init(genres: [10765])
        ),
        BrowseCategory(
            id: "horror",
            title: "Horror",
            group: .genres,
            backdropPath: "/rAOjnEFTuNysY7bot8zonhImGMh.jpg",
            movie: .init(genres: [27]),
            tv: .init(keywords: [315_058])
        ),
        BrowseCategory(
            id: "romance",
            title: "Romance",
            group: .genres,
            backdropPath: "/66Kn4XWhkuPkJxOJyPEx4U2CUfN.jpg",
            movie: .init(genres: [10749]),
            tv: .init(keywords: [9840])
        ),
        BrowseCategory(
            id: "animation",
            title: "Animation",
            group: .genres,
            backdropPath: "/g7CHF8gTLGooTbP4GznIGwaqAGL.jpg",
            movie: .init(genres: [16]),
            tv: .init(genres: [16])
        ),
        BrowseCategory(
            id: "documentary",
            title: "Documentary",
            group: .genres,
            backdropPath: "/2Nwbv0hrN8sThLvgooShcPqmFrO.jpg",
            movie: .init(genres: [99]),
            tv: .init(genres: [99])
        ),
        BrowseCategory(
            id: "history",
            title: "History & Period",
            group: .genres,
            backdropPath: "/8FCHJ21JBQOgATY2WI8vwYAiXg8.jpg",
            movie: .init(genres: [36]),
            tv: .init(keywords: [15060, 15126])
        ),
        BrowseCategory(
            id: "war",
            title: "War",
            group: .genres,
            backdropPath: "/hwNtEmmugU5Yd7hpfprNWI0DGIn.jpg",
            movie: .init(genres: [10752]),
            tv: .init(genres: [10768])
        ),
        BrowseCategory(
            id: "western",
            title: "Western",
            group: .genres,
            backdropPath: "/2oZklIzUbvZXXzIFzv7Hi68d6xf.jpg",
            movie: .init(genres: [37]),
            tv: .init(genres: [37])
        ),
        BrowseCategory(
            id: "music",
            title: "Music & Musicals",
            group: .genres,
            backdropPath: "/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg",
            movie: .init(genres: [10402]),
            tv: .init(keywords: [4344, 283_297])
        ),
        BrowseCategory(
            id: "feelgood",
            title: "Feel-Good",
            group: .moods,
            backdropPath: "/udYOmbW1JEZjVd726PWHlmptxPi.jpg",
            movie: .init(
                keywords: [383_896, 319_357, 335_803, 194_088, 334_465, 367_611, 377_619],
                withoutGenres: [27, 53, 80],
                withoutKeywords: [259_094, 286_125, 230_747]
            ),
            tv: .init(
                keywords: [383_896, 319_357, 335_803, 194_088, 334_465, 367_611, 377_619],
                withoutGenres: [80],
                withoutKeywords: [259_094, 286_125, 230_747]
            )
        ),
        BrowseCategory(
            id: "mindbending",
            title: "Mind-Bending",
            group: .moods,
            backdropPath: "/suaEOtk1N1sgg2MTM7oZd2cfVp3.jpg",
            movie: .init(keywords: [362_567, 326_438, 374_835, 9887, 3307, 157_171, 33465, 334_469, 10854]),
            tv: .init(keywords: [362_567, 326_438, 374_835, 9887, 3307, 157_171, 33465, 334_469, 10854])
        ),
        BrowseCategory(
            id: "dark",
            title: "Dark & Gritty",
            group: .moods,
            backdropPath: "/c6OLXfKAk5BKeR6broC8pYiCquX.jpg",
            movie: .init(keywords: [259_094, 207_268, 286_125, 230_747, 1541]),
            tv: .init(keywords: [259_094, 207_268, 286_125, 230_747, 1541])
        ),
        BrowseCategory(
            id: "darkcomedy",
            title: "Dark Comedy",
            group: .moods,
            backdropPath: "/TU9NIjwzjoKPwQHoHshkFcQUCG.jpg",
            movie: .init(keywords: [10123]),
            tv: .init(keywords: [10123])
        ),
        BrowseCategory(
            id: "heist",
            title: "Heists & Cons",
            group: .moods,
            backdropPath: "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg",
            movie: .init(keywords: [10051, 10453]),
            tv: .init(keywords: [10051, 10453])
        ),
        BrowseCategory(
            id: "truestory",
            title: "Based on a True Story",
            group: .moods,
            backdropPath: "/xXCuto8YVp5RFqBJ7yKmVmLOWpF.jpg",
            movie: .init(keywords: [9672]),
            tv: .init(keywords: [9672])
        ),
        BrowseCategory(
            id: "truecrime",
            title: "True Crime",
            group: .moods,
            backdropPath: "/3zCPI4JFc54xvLaJ71oI2KoP3az.jpg",
            movie: .init(keywords: [33722]),
            tv: .init(keywords: [33722])
        ),
        BrowseCategory(
            id: "timetravel",
            title: "Time Travel",
            group: .moods,
            backdropPath: "/7RyHsO4yDXtBv1zUU3mTpHeQ0d5.jpg",
            movie: .init(keywords: [4379, 10854]),
            tv: .init(keywords: [4379, 10854])
        ),
        BrowseCategory(
            id: "slowburn",
            title: "Slow Burn",
            group: .moods,
            backdropPath: "/gNdLJU9TxrpGx4dkZidjys3fyy0.jpg",
            movie: .init(keywords: [277_551, 245_724, 367_766]),
            tv: .init(keywords: [277_551, 245_724, 367_766])
        ),
        BrowseCategory(
            id: "cozymystery",
            title: "Cozy Mysteries",
            group: .moods,
            backdropPath: "/iWak7wT0j6ycCc8lKr4NBz9c7n5.jpg",
            movie: .init(
                keywords: [1735, 231_596, 12570, 207_046],
                withoutGenres: [27],
                withoutKeywords: [259_094, 286_125, 230_747, 10714]
            ),
            tv: .init(keywords: [1735, 231_596, 12570, 207_046], withoutKeywords: [259_094, 286_125, 230_747, 10714])
        ),
        BrowseCategory(
            id: "comingofage",
            title: "Coming of Age",
            group: .moods,
            backdropPath: "/tPpYGm2mVecue7Bk3gNVoSPA5qn.jpg",
            movie: .init(keywords: [10683]),
            tv: .init(keywords: [10683])
        ),
        BrowseCategory(
            id: "workplace",
            title: "Workplace",
            group: .moods,
            backdropPath: "/A4NwkQXTXElE5iAsne5RpvS8R2Z.jpg",
            movie: .init(keywords: [6282, 210_605, 1438]),
            tv: .init(keywords: [6282, 210_605, 1438])
        ),
        BrowseCategory(
            id: "psychological",
            title: "Psychological Thrillers",
            group: .moods,
            backdropPath: "/rlay2M5QYvi6igbGcFjq8jxeusY.jpg",
            movie: .init(keywords: [12565]),
            tv: .init(keywords: [12565])
        ),
        BrowseCategory(
            id: "dystopia",
            title: "Dystopian",
            group: .moods,
            backdropPath: "/tlm8UkiQsitc8rSuIAscQDCnP8d.jpg",
            movie: .init(keywords: [4565, 4458]),
            tv: .init(keywords: [4565, 4458])
        ),
        BrowseCategory(
            id: "space",
            title: "Space",
            group: .moods,
            backdropPath: "/vL5LR6WdxWPjLPFRLe133jXWsh5.jpg",
            movie: .init(keywords: [9882, 3801]),
            tv: .init(keywords: [9882, 3801])
        ),
        BrowseCategory(
            id: "superhero",
            title: "Superheroes",
            group: .moods,
            backdropPath: "/kIBK5SKwgqIIuRKhhWrJn3XkbPq.jpg",
            movie: .init(keywords: [9715]),
            tv: .init(keywords: [9715])
        ),
        BrowseCategory(
            id: "spy",
            title: "Spies",
            group: .moods,
            backdropPath: "/qzUIOTk0E3F1zjvYjcBRTKUTgf9.jpg",
            movie: .init(keywords: [470]),
            tv: .init(keywords: [470])
        ),
        BrowseCategory(
            id: "conspiracy",
            title: "Conspiracy",
            group: .moods,
            backdropPath: "/eHaazLxM5LRMh0ySkVy7SK6wUWt.jpg",
            movie: .init(keywords: [10410]),
            tv: .init(keywords: [10410])
        ),
        BrowseCategory(
            id: "legal",
            title: "Legal & Courtroom",
            group: .moods,
            backdropPath: "/xj1Sv1xm4Y0ydBueGuf10Y9qM0O.jpg",
            movie: .init(keywords: [33519, 214_780]),
            tv: .init(keywords: [33519, 214_780])
        ),
        BrowseCategory(
            id: "serialkiller",
            title: "Serial Killers",
            group: .moods,
            backdropPath: "/i5H7zusQGsysGQ8i6P361Vnr0n2.jpg",
            movie: .init(keywords: [10714]),
            tv: .init(keywords: [10714])
        ),
        BrowseCategory(
            id: "revenge",
            title: "Revenge",
            group: .moods,
            backdropPath: "/Ar7QuJ7sJEiC0oP3I8fKBKIQD9u.jpg",
            movie: .init(keywords: [9748]),
            tv: .init(keywords: [9748])
        ),
        BrowseCategory(
            id: "survival",
            title: "Survival",
            group: .moods,
            backdropPath: "/gqrnQA6Xppdl8vIb2eJc58VC1tW.jpg",
            movie: .init(keywords: [10349]),
            tv: .init(keywords: [10349])
        ),
        BrowseCategory(
            id: "smalltown",
            title: "Small Town",
            group: .moods,
            backdropPath: "/qVGpxnjrGlHaSTCqTQI6viBDSfp.jpg",
            movie: .init(keywords: [1415]),
            tv: .init(keywords: [1415])
        ),
        BrowseCategory(
            id: "foundfamily",
            title: "Found Family",
            group: .moods,
            backdropPath: "/ywQtHG17LZhAFZyZtBflhtFMtJ7.jpg",
            movie: .init(keywords: [248_927]),
            tv: .init(keywords: [248_927])
        ),
        BrowseCategory(
            id: "supernatural",
            title: "Supernatural",
            group: .moods,
            backdropPath: "/amZavErrjrdgDwhsIdpWxHNenIx.jpg",
            movie: .init(keywords: [6152]),
            tv: .init(keywords: [6152])
        ),
        BrowseCategory(
            id: "sports",
            title: "Sports",
            group: .moods,
            backdropPath: "/oGMomeS7bE43eN8SGJUaKvQnmud.jpg",
            movie: .init(keywords: [6075]),
            tv: .init(keywords: [6075])
        ),
        BrowseCategory(
            id: "food",
            title: "Food & Cooking",
            group: .moods,
            backdropPath: "/zeoaHdXRDd5IoUiMVsNhwTZm78B.jpg",
            movie: .init(keywords: [1918, 222_083, 240_810, 227_635]),
            tv: .init(keywords: [1918, 222_083, 240_810, 227_635])
        ),
        BrowseCategory(
            id: "satire",
            title: "Satire",
            group: .moods,
            backdropPath: "/bBQHALHRAaaORlPNXv7fNcRXYdx.jpg",
            movie: .init(keywords: [8201]),
            tv: .init(keywords: [8201])
        ),
        BrowseCategory(
            id: "book",
            title: "Based on a Book",
            group: .moods,
            backdropPath: "/zZqpAXxVSBtxV9qPBcscfXBcL2w.jpg",
            movie: .init(keywords: [818]),
            tv: .init(keywords: [818])
        ),
        BrowseCategory(
            id: "limited",
            title: "Limited Series",
            group: .formats,
            backdropPath: "/cq62fLH3vwOmiaLKMqkDI86tPtH.jpg",
            movie: nil,
            tv: .init(keywords: [11162])
        ),
        BrowseCategory(
            id: "docuseries",
            title: "Docuseries",
            group: .formats,
            backdropPath: "/qmRUwosX4BsCj6QanpBYScLl3Sp.jpg",
            movie: nil,
            tv: .init(genres: [99])
        ),
        BrowseCategory(
            id: "standup",
            title: "Stand-Up Comedy",
            group: .formats,
            backdropPath: "/9sfVyE3sP2dkCwDyV7UlYP5TAAR.jpg",
            movie: .init(keywords: [9716]),
            tv: nil
        ),
        BrowseCategory(
            id: "anime",
            title: "Anime",
            group: .formats,
            backdropPath: "/6oaL4DP75yABrd5EbC4H2zq5ghc.jpg",
            movie: .init(genres: [16], languages: ["ja"]),
            tv: .init(genres: [16], languages: ["ja"])
        ),
        BrowseCategory(
            id: "reality",
            title: "Reality & Competition",
            group: .formats,
            backdropPath: "/qnTBxxv7q4xVwgZBLb0vtILLelh.jpg",
            movie: nil,
            tv: .init(genres: [10764])
        ),
        BrowseCategory(
            id: "shortepisodes",
            title: "Short Episodes",
            group: .formats,
            backdropPath: "/5F0HVEgkgP99fEWDjPyikGt9jQi.jpg",
            movie: nil,
            tv: .init(withoutGenres: [10763, 10766, 10767], minRuntime: 10, maxRuntime: 30)
        ),
        BrowseCategory(
            id: "shortmovies",
            title: "Movies Under 100 Min",
            group: .formats,
            backdropPath: "/9n2tJBplPbgR2ca05hS5CKXwP2c.jpg",
            movie: .init(minRuntime: 60, maxRuntime: 99),
            tv: nil
        ),
        BrowseCategory(
            id: "epics",
            title: "Epic Movies",
            group: .formats,
            backdropPath: "/ctiw6FZK4N36LmkjSklWEbuvlq9.jpg",
            movie: .init(minRuntime: 150),
            tv: nil
        ),
        BrowseCategory(
            id: "anthology",
            title: "Anthologies",
            group: .formats,
            backdropPath: "/dg3OindVAGZBjlT3xYKqIAdukPL.jpg",
            movie: nil,
            tv: .init(keywords: [9706])
        ),
        BrowseCategory(
            id: "nature",
            title: "Nature & Wildlife",
            group: .formats,
            backdropPath: "/b8hPBW0NJmiIVzvQjT3CwIpAdzl.jpg",
            movie: .init(keywords: [221_355, 9902]),
            tv: .init(keywords: [221_355, 9902])
        ),
        BrowseCategory(
            id: "talk",
            title: "Talk & Late Night",
            group: .formats,
            backdropPath: "/bJROfBstoARn6vOqqPylYLpGYDH.jpg",
            movie: nil,
            tv: .init(genres: [10767])
        ),
        BrowseCategory(
            id: "classics",
            title: "Classics",
            group: .eras,
            backdropPath: "/w5IDXtifKntw0ajv2co7jFlTQDM.jpg",
            movie: .init(years: 1920 ... 1969),
            tv: .init(years: 1920 ... 1969)
        ),
        BrowseCategory(
            id: "1970s",
            title: "1970s",
            group: .eras,
            backdropPath: "/ejdD20cdHNFAYAN2DlqPToXKyzx.jpg",
            movie: .init(years: 1970 ... 1979),
            tv: .init(years: 1970 ... 1979)
        ),
        BrowseCategory(
            id: "1980s",
            title: "1980s",
            group: .eras,
            backdropPath: "/5bzPWQ2dFUl2aZKkp7ILJVVkRed.jpg",
            movie: .init(years: 1980 ... 1989),
            tv: .init(years: 1980 ... 1989)
        ),
        BrowseCategory(
            id: "1990s",
            title: "1990s",
            group: .eras,
            backdropPath: "/pNjh59JSxChQktamG3LMp9ZoQzp.jpg",
            movie: .init(years: 1990 ... 1999),
            tv: .init(years: 1990 ... 1999)
        ),
        BrowseCategory(
            id: "2000s",
            title: "2000s",
            group: .eras,
            backdropPath: "/vbk5CfaAHOjQPSAcYm6AoRRz2Af.jpg",
            movie: .init(years: 2000 ... 2009),
            tv: .init(years: 2000 ... 2009)
        ),
        BrowseCategory(
            id: "2010s",
            title: "2010s",
            group: .eras,
            backdropPath: "/iVped1djsF0tvGkvnHbzsE3ZPTF.jpg",
            movie: .init(years: 2010 ... 2019),
            tv: .init(years: 2010 ... 2019)
        ),
        BrowseCategory(
            id: "2020s",
            title: "2020s",
            group: .eras,
            backdropPath: "/2meX1nMdScFOoV4370rqHWKmXhY.jpg",
            movie: .init(years: 2020 ... 2029),
            tv: .init(years: 2020 ... 2029)
        ),
        BrowseCategory(
            id: "acclaimed",
            title: "Critically Acclaimed",
            group: .acclaimed,
            backdropPath: "/zqkmTXzjkAgXmEWLRsY4UpTWCeo.jpg",
            movie: .init(minRating: 7.8, minVotes: 1500),
            tv: .init(minRating: 8.3, minVotes: 1000)
        ),
        BrowseCategory(
            id: "hiddengems",
            title: "Hidden Gems",
            group: .acclaimed,
            backdropPath: "/e2QAGrEmbpmZpMymDRkDisJkvg9.jpg",
            movie: .init(minRating: 7.4, minVotes: 80, maxVotes: 900),
            tv: .init(minRating: 7.8, minVotes: 40, maxVotes: 250)
        ),
        BrowseCategory(
            id: "crowdpleasers",
            title: "Crowd Pleasers",
            group: .acclaimed,
            backdropPath: "/1jHxkVXMI5s3vRiyiZooUy1shB5.jpg",
            movie: .init(minRating: 7.0, minVotes: 8000),
            tv: .init(minRating: 7.5, minVotes: 3000)
        ),
        BrowseCategory(
            id: "korean",
            title: "Korean",
            group: .languages,
            backdropPath: "/rwf5SUTiEsmfkXAgy15R0UtJUtv.jpg",
            movie: .init(languages: ["ko"]),
            tv: .init(languages: ["ko"])
        ),
        BrowseCategory(
            id: "japanese",
            title: "Japanese",
            group: .languages,
            backdropPath: "/mMtUybQ6hL24FXo0F3Z4j2KG7kZ.jpg",
            movie: .init(languages: ["ja"]),
            tv: .init(languages: ["ja"])
        ),
        BrowseCategory(
            id: "spanish",
            title: "Spanish",
            group: .languages,
            backdropPath: "/xGexTKCJDkl12dTW4YCBDXWb1AD.jpg",
            movie: .init(languages: ["es"]),
            tv: .init(languages: ["es"])
        ),
        BrowseCategory(
            id: "british",
            title: "British",
            group: .languages,
            backdropPath: "/cClWTo3ftVXvV1sF8vlLuWfnlph.jpg",
            movie: .init(countries: ["GB"]),
            tv: .init(countries: ["GB"])
        ),
        BrowseCategory(
            id: "french",
            title: "French",
            group: .languages,
            backdropPath: "/fj0hwDJEOOHllRim2BMt5L7tbjf.jpg",
            movie: .init(languages: ["fr"]),
            tv: .init(languages: ["fr"])
        ),
        BrowseCategory(
            id: "nordic",
            title: "Nordic",
            group: .languages,
            backdropPath: "/P7d3lyBaYbAXVor6iB2avLvc4K.jpg",
            movie: .init(countries: ["SE", "NO", "DK", "FI", "IS"]),
            tv: .init(countries: ["SE", "NO", "DK", "FI", "IS"])
        ),
        BrowseCategory(
            id: "indian",
            title: "Indian",
            group: .languages,
            backdropPath: "/7VDLEHli74eLsYLNcq9djn1Gw76.jpg",
            movie: .init(countries: ["IN"]),
            tv: .init(countries: ["IN"])
        ),
        BrowseCategory(
            id: "german",
            title: "German",
            group: .languages,
            backdropPath: "/3jDXL4Xvj3AzDOF6UH1xeyHW8MH.jpg",
            movie: .init(languages: ["de"]),
            tv: .init(languages: ["de"])
        ),
        BrowseCategory(
            id: "italian",
            title: "Italian",
            group: .languages,
            backdropPath: "/6aNKD81RHR1DqUUa8kOZ1TBY1Lp.jpg",
            movie: .init(languages: ["it"]),
            tv: .init(languages: ["it"])
        ),
        BrowseCategory(
            id: "family",
            title: "Family Movie Night",
            group: .family,
            backdropPath: "/2XSeKDmIa2KxaiJy4J9e8FrIZhk.jpg",
            movie: .init(genres: [10751], certification: "PG"),
            tv: .init(genres: [10751])
        ),
        BrowseCategory(
            id: "kids",
            title: "Kids",
            group: .family,
            backdropPath: "/3Rfvhy1Nl6sSGJwyjb0QiZzZYlB.jpg",
            movie: .init(certification: "G"),
            tv: .init(genres: [10762])
        ),
        BrowseCategory(
            id: "teen",
            title: "Teen & High School",
            group: .family,
            backdropPath: "/weAYfu6FfrNxEDJ3xH1XpgQcqUv.jpg",
            movie: .init(keywords: [6270]),
            tv: .init(keywords: [6270])
        ),
    ]
}
