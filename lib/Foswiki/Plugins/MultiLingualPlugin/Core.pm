# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MultiLingualPlugin is Copyright (C) 2013-2017 Michael Daum http://michaeldaumconsulting.com
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

sub readIconMapping {
  my $this = shift;

  my $mappingFile = $Foswiki::cfg{MultiLingualPlugin}{FlagsTheme} || $Foswiki::cfg{PubDir}.'/'.$Foswiki::cfg{SystemWebName}.'/MultiLingualPlugin/flags/mapping.txt';

  my $IN_FILE;
  open( $IN_FILE, '<', $mappingFile ) || return '';

  foreach my $line (<$IN_FILE>) {
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
  our @c;

  sub _checkChunk {
    my $chunk = shift;

    #writeDebug("chunk $chunk");

    if ($chunk eq '[[' || $chunk eq ']]' || $chunk eq '][') {
      $chunk =~ s/(\[|\])/~$1/g;
    } elsif ($chunk eq '[' || $chunk eq '') {       # "[" or end
      return $chunk if $in_group; # let Locale::Maketext generate the proper error message
      $in_group = 1;
    } elsif ($chunk eq ']') {  # "]"
      return $chunk unless $in_group; # let Locale::Maketext generate the proper error message

      $in_group = 0;
      my ($method, @params) = split(/,/, $c[-1], -1);

      #print STDERR "method='$method'\n";
      throw Error::Simple("invalid method $method") 
        unless $method =~ /^(_\*|_\-?\d+|\*|\#|quant|numf|sprintf|numerate)$/;
    } 

    push @c, $chunk;

    return $chunk;
  }


  $text =~ 
      s/(
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
  my ($this, $params, $theTopic, $theWeb) = @_;

  # param
  my $langCode = $params->{language};

  # preference value
  $langCode = Foswiki::Func::getPreferencesValue("CONTENT_LANGUAGE")
    if !defined($langCode) || $langCode eq '';

  if (defined $langCode && $langCode ne '') {
    if ($langCode eq 'detect') {
      $langCode = '';
    } else {
      $langCode = Foswiki::Func::expandCommonVariables($langCode);
    }
  } 

  # i18n
  $langCode =  $this->{session}->i18n->language()
    if !defined($langCode) || $langCode eq '';

  $langCode = lc($langCode);

  my $key = $langCode;
  $key =~ s/-/_/g; # to be able to specify a tai translation using zh_tw="..." as a parameter

  my $text = $params->{$key};
  $text = $params->{_DEFAULT} unless defined $text; 
  $text = '' unless defined $text;

  return '' if $text eq '';

  $theWeb = $params->{web} if defined $params->{web};

  my $lexiconTopics = $params->{lexicon};
  $lexiconTopics = Foswiki::Func::getPreferencesValue("CONTENT_LEXICON", $theWeb)
    if !defined($lexiconTopics) || $lexiconTopics eq '';

  $lexiconTopics = 'WebLexicon'
    if (!defined($lexiconTopics) || $lexiconTopics eq '')
    && Foswiki::Func::topicExists($theWeb, 'WebLexicon');

  if (defined $lexiconTopics && $lexiconTopics ne "") {
    $lexiconTopics = Foswiki::Func::expandCommonVariables($lexiconTopics, $theTopic, $theWeb);
    my $lexiconWeb = $theWeb;
    my $languageName = getLanguageOfCode($langCode);
    foreach my $lexiconTopic (split(/\s*,\s*/, $lexiconTopics)) {
      ($lexiconWeb, $lexiconTopic) = Foswiki::Func::normalizeWebTopicName($lexiconWeb, $lexiconTopic);
      my $entry = $this->getLexiconEntry($lexiconWeb, $lexiconTopic, $text);
      my $translation;
      if ($entry && $languageName) {
        my $key = fieldTitle2FieldName("$languageName ($langCode)");
        $translation = $entry->{$key} if defined $entry->{$key} && $entry->{$key} ne '';
      }
      if (defined $translation && $translation ne "") {
        $text = $translation;
        last;
      }
    }
  }
    
  my $args = $params->{args};
  $args = '' unless defined $args;

  my $split = $params->{splitargs} || '\s*,\s*';
  my @args = split($split, $args);

  # gather enumerated args arg1, arg2, ...
  foreach my $key (keys %$params) {
    if ($key =~ /^arg(\d+)$/) {
      $args[$1] = $params->{$key};
    }
  }

  push @args, '' for (0...100); # fill up args in case there are more placeholders in text

  my $error;
  try {
    $text = preProcessMaketextParams($text);
    $text = $this->{session}->i18n->maketext($text, @args);

    # backwards compatibility
    $text =~ s/&&/\&/g;

  } catch Error::Simple with {
    $error = shift;
    $error =~ s/ (via|at) .*$//s;
  };

  if (defined $error) {
    return "<span class='foswikiAlert'><noautolink><literal>$error</literal></noautolink></span>";
  }

  return Foswiki::Func::decodeFormatTokens($text);
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

  my $enabledLanguages = $this->{session}->i18n->enabled_languages();

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
  if ($theSort ne 'off') {
    $theSort = 'code' if $theSort eq 'on';
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

  return code2language($code, LOCALE_CODE_ALPHA_2) || '';
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
  }

  return $label;
}

sub getLexiconEntry {
  my ($this, $web, $topic, $text) = @_;

  my $lexicon = $this->{lexicons}{$web.'.'.$topic};
  unless (defined $lexicon) {
    $lexicon = {};
    writeDebug("reading lexicon from $web.$topic");

    my ($meta) = Foswiki::Func::readTopic($web, $topic);
    foreach my $entry  ($meta->find("LEXICON")) {
      next unless $entry->{String};
      $lexicon->{$entry->{String}} = $entry;
    }

    $this->{lexicons}{$web.'.'.$topic} = $lexicon;
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
