// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations_en.dart';
import 'app_localizations_ext.dart';

// ignore_for_file: type=lint

/// The translations for extensionEnglish (`en`).
class AppLocalizationsExtEn extends AppLocalizationsEn
    with AppLocalizationsExt {
  @override
  List<Map<String, dynamic>> get defaultCharacters => [
        {
          "id": "2",
          "name": "Mentor",
          "tags": ["wisdom", "validation", "big-picture"],
          "avatar": "9",
          "first_message":
              "I'm here. No need to report anything. Start with the one sentence that is already on your mind.",
        },
        {
          "id": "3",
          "name": "Auntie",
          "tags": ["warmth", "care", "health"],
          "avatar": "18",
          "first_message":
              "Come sit for a bit. Are we venting today, or should I pour you something warm first?",
        },
        {
          "id": "4",
          "name": "Moonlight",
          "tags": ["distant", "beauty", "nostalgia"],
          "avatar": "3",
          "first_message":
              "I'm here. You can say it slowly, or just leave today here for a while.",
        },
        {
          "id": "5",
          "name": "Bestie",
          "tags": ["bestie", "venting", "company"],
          "avatar": "5",
          "first_message":
              "I'm here. Who annoyed you today, or do we have something to brag about?",
        },
        {
          "id": "counselor",
          "name": "Counselor",
          "tags": ["listening", "emotional support", "self-awareness"],
          "avatar": "14",
          "first_message":
              "I'm here. You can start with the part that feels most stuck, or we can sit quietly for a moment first.",
        }
      ];

  @override
  String get pkmPARAStructureExample =>
      '''## P.A.R.A. Knowledge Base Structure Example (Flexibly organized based on actual user input):
│
├── Projects
│   ├── 2025 Sanya Spring Festival Trip/      <-- Involves itinerary, flights, hotels, use folder
│   │   ├── Itinerary and Schedule.md
│   │   └── Flight and Hotel Confirmations.md
│   ├── New House Renovation/                 <-- Involves long-term multi-file management
│   │   ├── Renovation Budget and Expenses.md
│   │   └── Soft Furnishing Shopping List.md
│   ├── Get Driver's License C1.md            <-- Single goal, a single file is enough
│   └── December Work Report Preparation.md
│
├── Areas
│   ├── Health and Medical/
│   │   ├── Family Medical Checkup Reports.md
│   │   └── Fitness Log and Weight Records.md  <-- Suitable for appending
│   ├── Financial Management/
│   │   ├── Annual Family Insurance Policies.md
│   │   └── Credit Card Reminders and Bills.md
│   ├── Personal ID and Archives/
│   │   └── Passport and ID Card Backups.md
│   └── Career Development/
│       └── Personal Resume Maintenance.md      <-- Will be updated continuously over time
│
├── Resources
│   ├── Cooking and Food/
│   │   ├── Weight Loss Meal Recipes.md
│   │   └── Home Appliance User Guides.md
│   ├── Reading and Movies/
│   │   ├── Movie Watchlist.md
│   │   └── Reading Notes.md
│   ├── Travel Inspiration Vault/              <-- Want to go but no date yet
│   │   └── Kyoto Travel Guide Backups.md
│   └── Home Organization Tips/
│       └── Tidying and Storage Notes.md
│
└── Archives
    ├── [Completed] Buy First Car.md
    └── [Expired] Old Rental Contract Data/
           ├── Rental Contract.md
           └── Rent Payment Records.md''';

  @override
  String get timelineCardLanguageInstruction =>
      'All generated text (title, summary, etc.) must be in English language.';

  @override
  String get pkmFileLanguageInstruction =>
      'P.A.R.A. root category folders (Projects, Areas, Resources, Archives) must always use these exact English names. All other file contents, subfolder names, and filenames inside the P.A.R.A. knowledge base MUST be in English.';

  @override
  String get pkmInsightLanguageInstruction =>
      'All insight text and summary text MUST be in English.';

  @override
  String get commentLanguageInstruction =>
      'All output must be in English language.';



  @override
  String get scheduleAggregatorLanguageInstruction =>
      '**Important**: All output text (editorial_intro, quote_blocks, conflict descriptions) must be in **English**.';

  @override
  String get assetAnalysisLanguageInstruction =>
      'IMPORTANT: You must respond in English.';

  @override
  String get userLanguageInstruction => 'User Language: English (en)';

  @override
  String get chatLanguageInstruction =>
      'All output must be in English language.';

  @override
  String get memorySummarizeLanguageInstruction => 'FORCE OUTPUT in English.';

  @override
  String get memorySummarizeIdentityHeader => '# Identity';

  @override
  String get memorySummarizeInterestsHeader => '# Skills & Interests';

  @override
  String get memorySummarizeAssetsHeader => '# Assets & Environment';

  @override
  String get memorySummarizeFocusHeader => '# Current Focus';

  @override
  String get oauthHintTitle => 'Authorization tip';

  @override
  String get oauthHintMessage =>
      'The authorization page will open in the browser.\n\n'
      'If the page does not respond after you tap Allow on the confirmation screen, '
      'try this: keep the page open, go to the home screen or app switcher, '
      'then tap Memex again to bring it to the foreground.';

  @override
  String get oauthSuccessTitle => 'Authorization successful';

  @override
  String get oauthSuccessMessage =>
      'You can now close this browser and return to Memex.';

  @override
  String get sharePreviewTitle => 'Share Preview';

  @override
  String get shareNow => 'Share';

  @override
  String get sharedFromMemex => 'Shared from Memex';

  @override
  String get appTagline => 'Record the Spark, Architect the Soul';

  @override
  String get shareDetailStyle => 'Detail';

  @override
  String get shareCardStyle => 'Card';

  @override
  String get shareHideBranding => 'No Mark';

  @override
  String get shareShowBranding => 'Mark';
}
