# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MultiLingualPlugin is Copyright (C) 2013-2024 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::MultiLingualPlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Locale::Language;
use Locale::Country;
use Error qw(:try);

our $doneAliases = 0;
use constant TRACE => 0;

sub writeDebug {
  print STDERR "MultiLingualPlugin::Core - $_[0]\n" if TRACE;
}

sub new {
  my $class = shift;
  my $session = shift || $Foswiki::Plugins::SESSION;

  my $this = bless({ @_ }, $class);

  $this->{session} = $session;

  if (defined $Foswiki::cfg{MultiLingualPlugin}{Aliases} && !$doneAliases) {
    foreach my $key (keys %{$Foswiki::cfg{MultiLingualPlugin}{Aliases}}) {
      my $val = $Foswiki::cfg{MultiLingualPlugin}{Aliases}{$key};
      Locale::Country::add_country_code_alias($val, $key, LOCALE_CODE_ALPHA_2);
    }
    $doneAliases = 1;
  }

  $this->readIconMapping();

  return $this;
}

sub finish {
  my $this = shift;

  undef $this->{_lexiconTopics};
}

sub readIconMapping {
  my $this = shift;

  my $mappingFile = $Foswiki::cfg{MultiLingualPlugin}{FlagsTheme} || $Foswiki::cfg{PubDir}.'/'.$Foswiki::cfg{SystemWebName}.'/MultiLingualPlugin/flags/mapping.txt';

  my $IN_FILE;
  open( $IN_FILE, '<', $mappingFile ) || return '';

  while (my $line = <$IN_FILE>) {
    $line =~ s/#.*$//;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next if $line =~ /^$/;

    if ($line =~ /^(.*?)\s*=\s*(.*?)$/) {
      my $key = $1;
      my $val = $2;
      if ($key eq 'sizes') {
        $this->{flags_sizes} = [ reverse split(/\s*,\s*/, $val)];
      } else {
        $this->{flags}{$key} = $val;
      }
    }
  }
  close($IN_FILE);

  $this->{flags_sizes} = ['16'] unless defined $this->{flags_sizes};
} 

# secure text before passing ot to Locale::Maketext
sub preProcessMaketextParams {
  my $text = shift;

  writeDebug("called preProcessMaketextParams($text)");

  # from Locale::Maketext
  our $in_group = 0;
  our @c = ();

  sub _checkChunk { ## no critic
    my $chunk = shift;

    if ($chunk eq '[[' || $chunk eq ']]' || $chunk eq '][') {
      $chunk =~ s/(\[|\])/~$1/g;
    } elsif ($chunk eq '[' || $chunk eq '') {       # "[" or end
      return $chunk if $in_group; # let Locale::Maketext generate the proper error message
      $in_group = 1;
    } elsif ($chunk eq ']') {  # "]"
      return $chunk unless $in_group; # let Locale::Maketext generate the proper error message

      $in_group = 0;
      my ($method, @params) = split(/,/, $c[-1], -1);

      unless ($method =~ /^(_\*|_\-?\d+|\*|\#|quant|numf|sprintf|numerate)$/) {
        throw Error::Simple("invalid method $method") 
      }
    } 

    push @c, $chunk;

    return $chunk;
  }

  $text =~ 
      s/(
          \[_\d\] # placeholder
          |
          \[\[ # starting bracket link
          |
          \]\] # endint bracket link
          |
          \]\[ # middle part of a link
          |
          [^\~\[\]]+  # non-~[] stuff (Capture everything else here)
          |
          ~.       # ~[, ~], ~~, ~other
          |
          \[          # [ presumably opening a group
          |
          \]          # ] presumably closing a group
          |
          ~           # terminal ~ ?
          |
          $
      )/_checkChunk($1)/xegs;

  writeDebug("result: $text");

  return $text;
}

sub TRANSLATE {
  my ($this, $params, $topic, $web) = @_;

  my $i18n = $this->{session}->i18n;

  my $doWarn = Foswiki::Func::isTrue($params->{warn}, 0);

  # param
  my $langCode = $params->{language};

  # preference value
  $langCode = Foswiki::Func::getPreferencesValue("CONTENT_LANGUAGE")
    if !defined($langCode) || $langCode eq '';

  if (defined $langCode && $langCode ne '') {
    if ($langCode eq 'detect') {
      $langCode = '';
    } else {
      #$langCode = Foswiki::Func::expandCommonVariables($langCode); DISABLED for performance reasons
    }
  } 

  # i18n
  $langCode =  $i18n->language()
    if !defined($langCode) || $langCode eq '';

  $langCode = lc($langCode);

  my $key = $langCode;
  $key =~ s/-/_/g; # to be able to specify a tai translation using zh_tw="..." as a parameter

  # get text 
  my $text = $params->{$key};

  # shortcut for simple inline translations
  if (defined $text && $text !~ /\[(_\*|_\-?\d+|\*|\#|quant|numf|sprintf|numerate)/) { 
    writeDebug("shortcut result $text");
    return Foswiki::Func::decodeFormatTokens($text);
  }

  $text = $params->{_DEFAULT} unless defined $text; 
  $text = '' unless defined $text;
  $text =~ s/^_+//g; # maketext args can't start with an underscore

  return '' if $text eq '';

  my $lexiconWeb = $params->{web} || $this->{session}{webName}; # NOTE: use base web, not current web
  my @lexiconTopics = ();
  push @lexiconTopics, [Foswiki::Func::normalizeWebTopicName($lexiconWeb, $params->{lexicon})] if $params->{lexicon};
  @lexiconTopics = $this->getLexiconTopics($lexiconWeb, $topic) unless @lexiconTopics;

  my $found = 0;
  if (@lexiconTopics) {
    my $languageName = getLanguageOfCode($langCode);
    foreach my $lexiconTopic (@lexiconTopics) {
      next unless $lexiconTopic;
      my $entry = $this->getLexiconEntry($lexiconTopic, $text);
      my $translation;
      if ($entry && $languageName) {
        my $key = fieldTitle2FieldName("$languageName ($langCode)");
        $translation = $entry->{$key} if defined $entry->{$key} && $entry->{$key} ne '';
      }
      if (defined $translation && $translation ne "") {
        $text = $translation . "\0"; # prevent translation loops
        $found = 1;
        last;
      }
    }
  }

  if (!$found || $text =~ /\[|\]/) {

    my $args = $params->{args};
    $args = '' unless defined $args;

    my $split = $params->{splitargs} || '\s*,\s*';
    my @args = split($split, $args);

    # gather enumerated args arg1, arg2, ...
    foreach my $key (keys %$params) {
      if ($key =~ /^arg(\d+)$/) {
        $args[$1-1] = $params->{$key};
      }
    }

    push @args, '' for (0...100); # fill up args in case there are more placeholders in text

    my $error;
    try {
      $text = preProcessMaketextParams($text);
      $text = $i18n->maketext($text, @args);

      # backwards compatibility
      $text =~ s/&&/\&/g;

    } catch Error::Simple with {
      $error = shift;
      $error =~ s/ (via|at) .*$//s;
    };

    return $error if defined $error && $doWarn;
  } else {
    #print STDERR "simple string $text\n";
  }

  $text =~ s/\0//g; # remove translation token

  return Foswiki::Func::decodeFormatTokens($text);
}

sub getLexiconTopics {
  my ($this, $web, $topic) = @_;

  $web =~ s/\//./g;
  my $key = "$web.$topic";


  unless (defined $this->{_lexiconTopics}{$key}) {
    my @lexiconTopics = ();

    # add existing web lexicon in this web
    push @lexiconTopics, 'WebLexicon' if Foswiki::Func::topicExists($web, 'WebLexicon');

    # add web lexicon preferences
    my $webLexicon = Foswiki::Func::getPreferencesValue("WEBLEXICON", $web) 
      || Foswiki::Func::getPreferencesValue("CONTENT_LEXICON", $web);
    push @lexiconTopics, split(/\s*,\s*/, $webLexicon) if $webLexicon;

    # add site lexicon fallback
    my $siteLexicon = Foswiki::Func::getPreferencesValue("SITELEXICON") || '';
    push @lexiconTopics, split(/\s*,\s*/, $siteLexicon) if $siteLexicon;

    #print STDERR "lexiconTopics($web.$topic): ".join(", ", @lexiconTopics)."\n";

    foreach (@lexiconTopics) {
      my ($lexiconWeb, $lexiconTopic) = Foswiki::Func::normalizeWebTopicName($web, $_);
      $lexiconWeb =~ s/\//./g;
      push @{$this->{_lexiconTopics}{$key}}, [$lexiconWeb, $lexiconTopic];
    }

  } else {
    #print STDERR "found lexionTopics($web.$topic) in cache\n";
  }

  return @{$this->{_lexiconTopics}{$key} // []};
}

# an improvement over the core LANGUAGES macro
sub LANGUAGES {
  my ($this, $params, $theTopic, $theWeb) = @_;

  my $languages = $params->{_DEFAULT};
  my $format = $params->{format};
  $format = '   * $language' unless defined $format;

  my $separator = $params->{separator};
  $separator = "\n" unless defined $separator;

  my $selection = $params->{selection} || '';
  $selection =~ s/\,/ /g;
  $selection = " $selection ";

  my $marker = $params->{marker};
  $marker = 'selected="selected"' unless defined $marker;

  my $include = $params->{include};
  my $exclude = $params->{exclude};

  my $enabledLanguages = $this->enabledLanguages();
  #print STDERR "enabled_languages=".join(", ", keys %$enabledLanguages)."\n";

  my @records = ();
  if (defined $languages) {
    foreach my $code (split(/\s*,\s*/, $languages)) {
      $code = $Foswiki::cfg{MultiLingualPlugin}{DefaultLanguage} || 'en' if $code eq 'detect' || $code eq 'default';
      push @records, {
        code => $code,
        name => $enabledLanguages->{$code} || getLanguageOfCode($code),
        language => getLanguageOfCode($code),
        label => getLabelOfCode($code),
        country => getCountryOfCode($code)
      };
    }
  } else {
    foreach my $code (keys %{$enabledLanguages}) {
      push @records, {
        code => $code,
        name => $enabledLanguages->{$code},
        language => getLanguageOfCode($code),
        label => getLabelOfCode($code),
        country => getCountryOfCode($code)
      };
    }
  }

  my $theSort = $params->{sort} || 'language';
  $theSort = 'code' if $theSort eq 'on';
  if ($theSort ne 'off') {
    @records = sort {($a->{$theSort}||'') cmp ($b->{$theSort}||'')} @records;
  }

  my @result = ();
  my $count = 0;
  foreach my $record (@records) {
    next if defined $include && $record->{code} !~ /$include/;
    next if defined $exclude && $record->{code} =~ /$exclude/;
    my $item = $format;
    $count++;
    $item =~ s/\$index/$count/g;
    $item =~ s/\$icon(?:\((.*?)\))?/$this->getFlagImage($record->{code}, $1||16)/ge;
    $item =~ s/\$name/$record->{name}/g;
    $item =~ s/\$code/$record->{code}/g;
    $item =~ s/\$label_name(?:\((.*?)\))?/$record->{label}.(($record->{label} eq $record->{name})?'':($1||' - ').$record->{name})/ge;
    $item =~ s/\$language_name(?:\((.*?)\))?/$record->{language}.(($record->{language} eq $record->{name})?'':($1||' - ').$record->{name})/ge;
    $item =~ s/\$language/$record->{language}/g;
    $item =~ s/\$label/$record->{label}/g;
    $item =~ s/\$country/$record->{country}/g;

    # backwards compatibility
    $item =~ s/\$langname/$record->{name}/g;
    $item =~ s/\$langtag/$record->{code}/g;

    my $mark = ($selection =~ / \Q$record->{code}\E /) ? $marker : '';
    $item =~ s/\$marker/$mark/g;
    push @result, $item;
  }

  return '' unless @result;


  my $header = $params->{header} || '';
  my $footer = $params->{footer} || '';

  my $result = Foswiki::Func::decodeFormatTokens($header.join($separator, @result).$footer);
  $result =~ s/\$count/$count/g;

  return $result;
}

sub enabledLanguages {
  my ($this) = @_;

  unless (defined $this->{enabledLanguages}) {

    # temporarily disable error messages in stderr
    $Locale::Country::obj->show_errors(0) if defined $Locale::Country::obj;

    my $enabledLanguages = $this->{session}->i18n->enabled_languages();
    $this->{enabledLanguages} = {};

    # weed out those not known to Locale::Codes
    foreach my $code (keys %{$enabledLanguages}) {
      if (getLanguageOfCode($code)) {
        $this->{enabledLanguages}{$code} = $enabledLanguages->{$code};
      } else {
        print STDERR "WARNING: $code unkown to Locale::Country\n" unless $code eq 'tlh'; # warn for unknown codes except klingon
      }
    }

    # enable it again
    $Locale::Country::obj->show_errors(1) if defined $Locale::Country::obj;
  }

  return $this->{enabledLanguages};
}

sub getFlagImage {
  my ($this, $code, $size) = @_;

  my $flag = $this->getFlag($code);
  return '' unless $flag;

  my $format = "<img src='%PUBURLPATH%/%SYSTEMWEB%/MultiLingualPlugin/flags/\$size/\$flag' width='\$size' alt='\$language' />";

  my $bestSize = 16;
  foreach my $s (@{$this->{flags_sizes}}) {
    if ($size >= $s) {
      $bestSize = $s;
      last;
    }
  }
  
  $format =~ s/\$size/$bestSize/g;
  $format =~ s/\$flag/$flag/g;

  return $format;
}

sub getFlag {
  my ($this, $key) = @_;

  my $flag;
  my $alias = $Foswiki::cfg{MultiLingualPlugin}{Aliases}{$key};

  $flag = $this->{flags}{$alias} if defined $alias;
  return $flag if defined $flag;

  $flag = $this->{flags}{$key};
  return $flag if defined $flag;

  return;
}

sub getCountryOfCode {
  my $code = shift;

  my $alias = $Foswiki::cfg{MultiLingualPlugin}{Aliases}{$code};
  $code = $alias if defined $alias;

  if ($code =~ /^\w+-(\w+)$/) {
    $code = $1;  
  }

  return code2country($code, LOCALE_CODE_ALPHA_2) || '';
}

sub getLanguageOfCode {
  my $code = shift;

  if ($code =~ /^(\w+)-\w+$/) {
    $code = $1;  
  }

  my $lang = code2language($code, LOCALE_CODE_ALPHA_2) || '';
  $lang =~ s/\(\d+\-\)//; # weed out Modern Greek (1453-)
  return $lang;
}

sub getLabelOfCode {
  my $code = shift;

  my $label;
  if ($code =~ /^(\w+)-(\w+)$/) {
    $code = $1;
    my ($lname, $cname) = ((code2language($1, LOCALE_CODE_ALPHA_2) || ''), (code2country($2, LOCALE_CODE_ALPHA_2) || ''));
    if ($lname && $cname) {
      $label = "$lname ($cname)";
    } elsif ($lname) {
      $label = "$lname ($2)";
    } elsif ($cname) {
      $label = "$1 ($cname)";
    } else {
      $label = "$code";
    }
  } else {
    $label = code2language($code, LOCALE_CODE_ALPHA_2) || "$code";
    $label =~ s/\(\d+\-\)//; # weed out Modern Greek (1453-)
  }

  return $label;
}

sub getLexiconEntry {
  my ($this, $lexiconTopic, $text) = @_;

  my $key = join(".", @$lexiconTopic);

  my $lexicon = $this->{lexicons}{$key};
  unless (defined $lexicon) {
    $lexicon = {};
    writeDebug("reading lexicon from $key");

    my ($meta) = Foswiki::Func::readTopic($lexiconTopic->[0], $lexiconTopic->[1]);
    foreach my $entry  ($meta->find("LEXICON")) {
      next unless $entry->{String};
      $lexicon->{$entry->{String}} = $entry;
    }

    $this->{lexicons}{$key} = $lexicon;
  }

  return $lexicon->{$text};
}

# from Foswiki::Form
sub fieldTitle2FieldName {
  my ($text) = @_;
  return '' unless defined($text);

  $text =~ s/!//g;
  $text =~ s/<nop>//g;    # support <nop> character in title
  $text =~ s/[^A-Za-z0-9_\.]//g;

  return $text;
}

1;
