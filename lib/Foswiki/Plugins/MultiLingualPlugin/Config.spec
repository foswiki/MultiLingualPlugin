# ---+ Extensions
# ---++ MultiLingualPlugin
# This is the configuration used by the <b>MultiLingualPlugin</b>.

# **BOOLEAN**
# If enabled then both settings - CONTENT_LANGUAGE and LANGUAGE will be kept in sync
# where the first determines the content and the latter the interface language.
$Foswiki::cfg{MultiLingualPlugin}{SyncUserInterface} = 1;

# **STRING**
# Default language
$Foswiki::cfg{MultiLingualPlugin}{DefaultLanguage} = 'en';

# **PERL**
# Alias codes, i.e. mapping retired codes to new ones
$Foswiki::cfg{MultiLingualPlugin}{Aliases} = {
  "en" => "gb",
  "ja" => "jp",
  "el" => "gr",
  "ko" => "kr",
  "uk" => "ua",
  "da" => "dk",
};

# **STRING**
# Flags theme file. Mapps language codes to images.
$Foswiki::cfg{MultiLingualPlugin}{FlagsTheme} = '$Foswiki::cfg{PubDir}/$Foswiki::cfg{SystemWebName}/MultiLingualPlugin/flags/mapping.txt';

1;
