#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use File::Temp qw/ tempfile tempdir /; # standard distribution


# binaries (change as needed)
my $bin_ffmpeg      = '/usr/bin/ffmpeg';
my $bin_dvdauthor   = '/usr/bin/dvdauthor';
my $bin_genisoimage = '/usr/bin/genisoimage';


# ----------- HERE BE DRAGONS ------------


# some globals
my $dir = tempdir( CLEANUP => 1 );
my $header_dvdauthor = "<dvdauthor dest=\"$dir/dvd\"><vmgm /><titleset><titles>";
my $content_dvdauthor = '';
my $footer_dvdauthor = '</titles></titleset></dvdauthor>';


# check for binaries
if (! -x $bin_ffmpeg or ! -x $bin_dvdauthor or ! -x $bin_genisoimage) {
  &print_help();
}


# subs
sub print_help {
  print "Usage:
  $0 <file1> [<file2> <file3> ...]

This program requires:
  - FFMpeg (binary: ffmpeg)
  - DVD Author (binary: dvdauthor)
  - GenIsoImage (binary: genisoimage)

";
}

#
# extract metadata from video file
#
sub extract_meta {
  my $f = shift;
  print "Extracting metadata from $f ...\n";

  # parse FFMpeg output for metadata
  open META, "$bin_ffmpeg -i \"$f\" 2>&1 |"
    or carp "Problem extracting metadata from $f, $?, $!";

  # length (in seconds), width (pixel), height, framerate
  my ($len, $w, $h, $fr);

  while (<META>) {
    #   Duration: 00:08:30.91, start: 0.000000, bitrate: 2488 kb/s
    #       Stream #0.0(und): Video: h264 (High), yuv420p, 1280x720, 2330 kb/s, 30 fps, 29.97 tbr, 1k tbn, 59.94 tbc
    #  Duration: 00:03:47.42, start: 0.000000, bitrate: 207 kb/s
    #      Stream #0.0: Video: h264 (Main), yuv420p, 320x240 [PAR 1:1 DAR 4:3], 157 kb/s, 29.97 tbr, 1k tbn, 59.94 tbc
    #
    if (/^\s*Duration: (\d+):(\d+):(\d+)\.\d+, start/) {
      $len = $3 + ($2 * 60) + ($1 * 60 * 60);
    }
    if (/^\s*Stream.*Video:.*, (\d+)x(\d+).*, (\d+\.?\d*) tbr/) {
      $w = $1;
      $h = $2;
      $fr = $3;
    }
  }
  #print "DEBUG (extract_meta) - $f - L: $len W: $w H: $h FR: $fr\n";
  return ($len, $w, $h, $fr);
}

#
# convert video in a format suitable for DVD
#
sub convert_file {
  my ($f, $aspect, $fr) = @_;
  my $newfn = $f;
  $newfn =~ s/\.[^\.]+$//; # strip extension
  $newfn =~ s/.*\///g; # strip path
  $newfn .= '.mpg';

  print "Converting $f to MPEG...\n";

  system($bin_ffmpeg, ('-i', $f, '-r', $fr, '-target', 'dvd', '-copyts', '-aspect', $aspect, "$dir/files/$newfn")) == 0
    or carp "Problem converting $f, $?";

  return $newfn;
}

#
# add an entry string to dvdauthor file content
#
sub add_dvdauthor_string {
  my ($f, $len) = @_;
  my $chapter_len = int($len / 5);
  my $chapter_str = '0';
  my $counter = 0;

  while($counter < $len) {
    $counter += $chapter_len;
    my $m = sprintf "%02d", int($counter / 60);
    my $s = sprintf("%02d", $counter % 60);
    $chapter_str .= ",$m:$s";
  }

  # <pgc><vob file="output.mpg" chapters="0,5:00,10:00,15:00,20:00"/></pgc>
  $content_dvdauthor .= "<pgc><vob file=\"$dir/files/$f\" chapters=\"$chapter_str\"/></pgc>";
}


# ----------
# main cycle
# ----------

# create subdirs
mkdir("$dir/dvd") or carp "Can't create dvd dir in $dir";
mkdir("$dir/files") or carp "Can't create dvd dir in $dir";

foreach my $file (@ARGV) {
  if (-f $file and -r $file) {
    # extract meta
    my ($l, $w, $h, $fr) = &extract_meta($file);

    # convert file (file name and aspect ratio)
    my $fn = &convert_file($file, ($w/$h), $fr);

    # add an entry to dvdauthor xml (new file name and length in seconds)
    &add_dvdauthor_string($fn, $l);

  } else {
    carp "$file unreadable or not a proper file, $!";
  }
}

print "Writing dvdauthor XML ...\n";

open my $dvdxml, '>', "$dir/dvdauthor.xml";
print $dvdxml $header_dvdauthor;
print $dvdxml $content_dvdauthor;
print $dvdxml $footer_dvdauthor;
close $dvdxml;

# debug
system("cat $dir/dvdauthor.xml");
print "\n\n";

print "Running dvdauthor ...\n";
system($bin_dvdauthor, '-x', "$dir/dvdauthor.xml");

print "Running genisoimage ...\n";
system($bin_genisoimage, '-dvd-video', '-o', 'dvdfromyt.iso', "$dir/dvd");

# end (tempdir will be removed)

