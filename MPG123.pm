package Audio::Play::MPG123;

use strict 'subs';
use Carp;

require Exporter;
use Fcntl;
use IPC::Open2;
use Cwd;
use File::Spec;
use Errno qw(EAGAIN EINTR);

BEGIN { $^W=0 } # I'm fed up with bogus and unnecessary warnings nobody can turn off.

@ISA = qw(Exporter);

@_consts = qw();
@_funcs = qw();

@EXPORT = @_consts;
@EXPORT_OK = @_funcs;
%EXPORT_TAGS = (all => [@_consts,@_funcs], constants => \@_consts);
$VERSION = '0.03';

$MPG123 = "mpg123";

$OPT_AUTOSTAT = 1;

sub new {
   my $self = bless {@_},shift;
   $self->start_mpg123;
   $self;
}

sub start_mpg123 {
   my $self=shift;
   $self->{r}=local *MPG123_READER;
   $self->{w}=local *MPG123_WRITER;
   $self->{pid}=open2($self->{r},$self->{w},$MPG123,'-R','-y','');
   die "Unable to start $MPG123" unless $self->{pid};
   fcntl $self->{r},F_SETFL,O_NONBLOCK;
   $self->parse(qr/^\@R (\S+)/,1) or die "Error during player startup: $self->{err}\n";
   $self->{version}=$1;
}

sub stop_mpg123 {
   my $self=shift;
   if (delete $self->{pid}) {
      print {$self->{w}} "\nQ\n";
      close $self->{w};
      close $self->{r};
   }
}

sub DESTROY {
   my $self=shift;
   $self->stop_mpg123;
}

sub line {
   my $self=shift;
   my $wait=shift;
   for(;;) {
      return $1 if $self->{buf} =~ s/^([^\n]*)\n+//;
      my $len = sysread $self->{r},$self->{buf},4096,length($self->{buf});
      # collapse out the most frequent event, very useful for slow machines
      $self->{buf} =~ s/^(?:\@F[^\n]*\n)+(?=\@F)//s;
      if (defined $len || ($! != EAGAIN && $! != EINTR)) {
         die "connection to mpg123 process lost: $!\n" if $len == 0;
      } else {
         if ($wait) {
            my $v = ""; vec($v,fileno($self->{r}),1)=1;
            select ($v, undef, undef, 60);
         } else {
            return ();
         }
      }
   }
}

sub parse {
   my $self=shift;
   my $re=shift;
   my $wait=shift;
   while (my $line = $self->line ($wait)) {
      if ($line =~ /^\@F (.*)$/) {
         $self->{frame}=[split /\s+/,$1];
         # sno rno tim1 tim2
      } elsif ($line =~ /^\@S (.*)$/) {
         @{$self}{qw(type layer samplerate
                     mode mode_extension
                     bpf channels
                     copyrighted error_protected
                     emphasis bitrate extension)}=split /\s+/,$1;
         $self->{state}=2;
      } elsif ($line =~ /^\@I ID3:(.{30})(.{30})(.{30})(....)(.{30})(.*)$/) {
         $self->{title}=$1;   $self->{artist}=$2;
         $self->{album}=$3;   $self->{year}=$4;
         $self->{comment}=$5; $self->{genre}=$6;
         $self->{$_} =~ s/\s+$// for qw(title artist album year comment genre);
      } elsif ($line =~ /^\@I (.*)$/) {
         $self->{title}=$1;
         delete @{$self}{qw(artist album year comment genre)}
      } elsif ($line =~ /^\@P (\d+)$/) {
         $self->{state}=$1;
         # 0 = stopped, 1 = paused, 2 = continued
      } elsif ($line =~ /^\@E (.*)$/) {
         $self->{err}=$1;
         return ();
      } elsif ($line !~ $re) {
         $self->{err}="Unknown response: $line";
         return ();
      }
      return $line if $line =~ $re;
   }
   delete $self->{err};
   return ();
}

sub poll {
   my $self=shift;
   my $wait=shift;
   $self->parse(qr//,1) if $wait;
   $self->parse(qr/^X\0/,0);
}

sub canonicalize_url {
   my $self=shift;
   my $url=shift;
   if ($url !~ m%^http://%) {
      $url=~s%^file://[^/]*/%%;
      $url=fastcwd."/".$url unless $url =~ /^\//;
   }
   $url;
}

sub load {
   my $self=shift;
   my $url=$self->canonicalize_url(shift);
   $self->{url}=$url;
   if (!-f $url) {
      $self->{err} = "No such file or directory: $url";
      return ();
   }
   print {$self->{w}} "LOAD $url\n";
   delete @{$self}{qw(frame type layer samplerate mode mode_extension bpf
                      channels copyrighted error_protected title artist album
                      year comment genre emphasis bitrate extension)};
   return $self->parse(qr{^\@S\s},1);
}

sub stat {
   my $self=shift;
   return unless $self->{state};
   print {$self->{w}} "STAT\n";
   $self->parse(qr{^\@F},1);
}

sub pause {
   my $self=shift;
   print {$self->{w}} "PAUSE\n";
   $self->parse(qr{^\@P},1);
}

sub jump {
   my $self=shift;
   print {$self->{w}} "JUMP $_[0]\n";
}

sub statfreq {
   my $self=shift;
   print {$self->{w}} "STATFREQ $_[0]\n";
}

sub stop {
   my $self=shift;
   print {$self->{w}} "STOP\n";
   $self->parse(qr{^\@P},1);
}

sub IN {
   $_[0]->{r};
}

sub tpf {
   my $self=shift;
   ($self->{layer}>1 ? 1152 : 384) / $self->{samplerate};
}

for my $field (qw(title artist album year comment genre state url
                  type layer samplerate mode mode_extension bpf
                  channels copyrighted error_protected title artist album
                  year comment genre emphasis bitrate extension)) {
  *{$field} = sub { shift->{$field} };
}

sub error { shift->{err} }

1;
__END__

=head1 NAME

Audio::Play::MPG123 - a frontend to mpg123 version 0.59r and beyond.

=head1 SYNOPSIS

  use Audio::Play::MPG123;
  
  $player = new Audio::Play::MPG123;
  $player->load("kult.mp3");
  print $player->artist,"\n";
  $player->poll(1) until $player->stat == 0;

  $player->load("http://x.y.z/kult.mp3");

  # see also mpg123sh from the tarball

=head1 DESCRIPTION

This is a frontend to the mpg123 player. It works by starting an external
mpg123 process with the C<-R> option and feeding commands to it.

=head2 METHODS

=over 4

=item new

This creates a new player object and also starts the mpg123 process.

=item load(<path or url>)

Immediately loads the specified file (or url, http:// and file:// forms
supported) and starts playing it.

=item pause

Pauses or unpauses the song. C<state> can be used to find out about the
current mode.

=item jump

Jumps to the specified frame of the song. If the number is prefixed with
"+" or "-", the jump is relative, otherweise it is absolute.

=item stop

Stops the currently playing song and unloads it.

=item framerate(rate)

Sets the rate at which automatic frame updates are sent by mpg123. C<0>
turns it off, everything else is the average number of frames between
updates.  This can be a floating pount value, i.e.

 $player->framerate (0.5/$player->tpf);

will set two updates per sond (one every half a second).

=item state

Returns the current state of the player:

 0  stopped, not playing anything
 1  paused, song loaded but not playing
 2  playing, song loaded and playing

=item poll(<wait>)

Parses all outstanding events and status information. If C<wait> is zero
it will only parse as many messages as are currently in the queue, if it
is one it will wait until at least one event occured.

This can be used to wait for the end of a song, for example. This function
should be called regularly, since mpg123 will stop playing when it can't
write out events because the perl program is no longer listening...

=item title artist album year comment genre url type layer samplerate mode mode_extension bpf channels copyrighted error_protected title artist album year comment genre emphasis bitrate extension

These accessor functions return information about the loaded
song. Information about the C<artist>, C<album>, C<year>, C<comment> or
C<genre> might not be available and will be returned as C<undef>.

=item tpf

Returns the "time per frame", i.e. the time in seconds for one frame. Useful with the C<jump>-method:

 $player->jump (60/$player->tpf);

Jumps to second 60.

=item IN

returns the input filehandle from the mpg123 player. This can be used for selects() or poll().

=back

=head1 AUTHOR

Marc Lehmann <pcg@goof.com>.

=head1 SEE ALSO

perl(1).

=cut
