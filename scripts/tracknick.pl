# created for irssi 0.7.98, Copyright (c) 2000 Timo Sirainen

# Are you ever tired of those people who keep changing their nicks?
# Or maybe you just don't like someone's nick?
# This script lets you see them with the real nick all the time no matter
# what nick they're currently using.

# Features:
#  - when you first join to channel the nick is detected from real name
#  - when the nick join to channel, it's detected from host mask
#  - keeps track of parts/quits/nick changes
#  - /find[realnick] command for seeing the current "fake nick"
#  - all public messages coming from the nick are displayed as coming from
#    the real nick.
#  - all other people's replies to the fake nick are changed to show the
#    real nick instead ("fakenick: hello" -> "realnick: hello")
#  - if you reply to the real nick, it's automatically changed to the 
#    fake nick

# TODO:
#  - ability to detect always from either address or real name (send whois
#    requests after join)
#  - don't force the trackchannel
#  - nick completion should complete to the real nick too (needs changes
#    to irssi code, perl module doesn't recognize "completion word" signal)
#  - support for runtime configuration + multiple nicks
#  - support for /whois and some other commands? private messages?

use strict;
use Irssi;
use Irssi::Irc;
use vars qw($VERSION %IRSSI); 
$VERSION = "0.02";
%IRSSI = (
    authors     => "Timo Sirainen",
    contact	=> "tss\@iki.fi", 
    name        => "tracknick",
    description => "Are you ever tired of those people who keep changing their nicks? Or maybe you just don't like someone's nick? This script lets you see them with the real nick all the time no matter what nick they're currently using.",
    license	=> "Public Domain",
    url		=> "http://irssi.org/",
    changed	=> "2019-06-08"
);

my $trackchannel;
my $realnick;
my $address_regexp;
my $realname_regexp;

my $fakenick = '';

sub event_nick {
	my ( $server, $newnick, $nick, $address) = @_;
	$newnick = substr($newnick, 1) if ($newnick =~ /^:/);

	$fakenick = $newnick if ($nick eq $fakenick)
}

sub event_join {
	my ( $server, $data, $nick, $address) = @_;

	if (!$fakenick && $data =~ m/$trackchannel/ &&
	    $address =~ /$address_regexp/) {
		$fakenick = $nick;
	}
}

sub event_part {
	my ($server, $data, $nick, $address) = @_;
        my ($channel, $reason) = $data =~ /^(\S*)\s:(.*)/;

	$fakenick = '' if ($fakenick eq $nick && $channel eq $trackchannel);
}

sub event_quit {
	my ($server, $data, $nick, $address) = @_;

	$fakenick = '' if ($fakenick eq $nick);
}

sub event_wholist {
	my ($channel) = @_;

	find_realnick($channel) if ($channel->{name} eq $trackchannel);
}

sub find_realnick {
	my ($channel) = @_;

	my @nicks = $channel->nicks();
	$fakenick = '';
	foreach my $nick (@nicks) {
		my $realname = $nick->{realname};
		if ($realname =~ /$realname_regexp/i) {
			$fakenick = $nick->{nick};
			last;
		}
	}
}

sub sig_public {
	my ($server, $msg, $nick, $address, $target) = @_;

	return if ($target ne $trackchannel || !$fakenick ||
		   $fakenick eq $realnick);

	if ($nick eq $fakenick) {
		# text sent by fake nick - change it to real nick
		send_real_public($server, $msg, $nick, $address, $target);
		return;
	}

	if ($msg =~ /^$fakenick([:',].*)/) {
		# someone's message starts with the fake nick,
		# automatically change it to real nick
		$msg = $realnick.$1;
		Irssi::signal_emit("message public", $server, $msg,
				   $nick, $address, $target);
		Irssi::signal_stop();
	}
}

sub send_real_public
{
	my ($server, $msg, $nick, $address, $target) = @_;

	my $channel = $server->channel_find($target);
	return if (!$channel);

	my $nickrec = $channel->nick_find($nick);
	return if (!$nickrec);

	# create temporarily the nick to the nick list so that
	# nick mode can be displayed correctly
	my $newnick = $channel->nick_insert($realnick,
		$nickrec->{op}, 
		$nickrec->{halfop},
		$nickrec->{voice},
		0);

	Irssi::signal_emit("message public", $server, $msg,
			   $realnick, $address, $target);
	$channel->nick_remove($newnick);
	Irssi::signal_stop();
}

sub sig_send_text {
	my ($data, $server, $item) = @_;

	return if (!$fakenick || !$item || 
		   $item->{name} ne $trackchannel);

	if ($fakenick ne $realnick && $data =~ /^$realnick([:',].*)/) {
		# sending message to realnick, change it to fakenick
		$data = $fakenick.$1;
		Irssi::signal_emit("send text", $data, $server, $item);
		Irssi::signal_stop();
	}
}

sub cmd_realnick {
	if ($fakenick) {
		Irssi::print("$realnick is currently with nick: $fakenick");
	} else {
		Irssi::print("I can't find $realnick currently.");
	}
}

sub sig_setup_changed {
	$address_regexp = Irssi::settings_get_str($IRSSI{name}.'_'.'address_regexp');
	$realname_regexp = Irssi::settings_get_str($IRSSI{name}.'_'.'realname_regexp');
	my $tc = Irssi::settings_get_str($IRSSI{name}.'_'.'trackchannel');
	if ( $tc ne $trackchannel) {
		$fakenick = '';
		$trackchannel= $tc;
	}
	my $rn = Irssi::settings_get_str($IRSSI{name}.'_'.'realnick');
	if ( $rn ne $realnick) {
		Irssi::command_unbind("find$realnick", 'cmd_realnick');
		Irssi::command_bind("find$rn", 'cmd_realnick');
		$fakenick = '';
		$realnick= $rn;
	}
	my $channel = Irssi::channel_find($trackchannel);
	find_realnick($channel) if ($channel);
}

Irssi::settings_add_str($IRSSI{name} ,$IRSSI{name}.'_'.'trackchannel', '#channel');
Irssi::settings_add_str($IRSSI{name} ,$IRSSI{name}.'_'.'realnick', 'nick');
Irssi::settings_add_str($IRSSI{name} ,$IRSSI{name}.'_'.'address_regexp', 'user@address.fi$');
Irssi::settings_add_str($IRSSI{name} ,$IRSSI{name}.'_'.'realname_regexp', 'first.*lastname');

Irssi::signal_add('setup changed', \&sig_setup_changed);
Irssi::signal_add('event nick', 'event_nick');
Irssi::signal_add('event join', 'event_join');
Irssi::signal_add('event part', 'event_part');
Irssi::signal_add('event quit', 'event_quit');
Irssi::signal_add('message public', 'sig_public');
Irssi::signal_add('send text', 'sig_send_text');
Irssi::signal_add('channel wholist', 'event_wholist');

sig_setup_changed();
