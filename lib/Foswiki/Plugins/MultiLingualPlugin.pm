# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MultiLingualPlugin is Copyright (C) 2013-2016 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::MultiLingualPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();

our $VERSION = '2.20';
our $RELEASE = '08 Mar 2016';
our $SHORTDESCRIPTION = 'Support for a multi lingual Foswiki';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  Foswiki::Func::registerTagHandler('LANGUAGES', sub { return getCore()->LANGUAGES(@_); });
  Foswiki::Func::registerTagHandler('DEFAULTLANGUAGE', sub { 
    my $session = shift;
    if ($Foswiki::cfg{MultiLingualPlugin}{SyncUserInterface}) {
      return $session->i18n->language();
    } else {
      return $Foswiki::cfg{MultiLingualPlugin}{DefaultLanguage} || 'en'; 
    }
  });
  Foswiki::Func::registerTagHandler('TRANSLATE', sub { return getCore()->TRANSLATE(@_); });

  return 1;
}

sub finishPlugin {
  undef $core;
}

sub beforeSaveHandler {
  my ($text, $topic, $web, $meta) = @_;

  return unless $Foswiki::cfg{MultiLingualPlugin}{SyncUserInterface};

  my $contentLanguage = $meta->get('PREFERENCE', 'CONTENT_LANGUAGE');
  if (defined $contentLanguage) {

    $contentLanguage = $contentLanguage->{value};
    if ($contentLanguage ne '' && $contentLanguage ne 'detect') {

      #my $session = $Foswiki::Plugins::SESSION;
      #my $enabledLanguages = $session->i18n->enabled_languages();
      #return unless defined $enabledLanguages{$contentLanguage};

      # sync content language and interface language
      $meta->putKeyed('PREFERENCE', { 
        name => 'LANGUAGE', 
        title => 'LANGUAGE', 
        type => 'Local', 
        value => $contentLanguage} 
      );
      return;
    }
  }

  $meta->remove('PREFERENCE', 'LANGUAGE');
}

sub getCore {

  unless (defined $core) {
    require Foswiki::Plugins::MultiLingualPlugin::Core;
    $core = new Foswiki::Plugins::MultiLingualPlugin::Core();
  }

  return $core;
}

1;
