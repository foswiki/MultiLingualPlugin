# ---+ Extensions
# ---++ MultiLingualPlugin
# This is the configuration used by the <b>MultiLingualPlugin</b>.

# **BOOLEAN**
$Foswiki::cfg{MultiLingualPlugin}{Debug} = 1;

# **STRING**
# Default language
$Foswiki::cfg{MultiLingualPlugin}{DefaultLanguage} = 'en';

# **PERL**
# Alias codes
$Foswiki::cfg{MultiLingualPlugin}{Aliases} = {
  "en" => "gb",
};

# **STRING**
# Flags theme file. Mapps language codes to images.
$Foswiki::cfg{MultiLingualPlugin}{FlagsTheme} = '$Foswiki::cfg{PubDir}/$Foswiki::cfg{SystemWebName}/MultiLingualPlugin/flags/mapping.txt';

1;
