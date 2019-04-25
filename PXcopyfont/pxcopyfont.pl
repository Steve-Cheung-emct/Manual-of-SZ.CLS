#!/usr/bin/perl
# pxcopyfont
#
use strict;
my $prog_name = "pxcopyfont";
my $version = "0.7.1";
my $mod_date = "2010/05/05";
use Data::Dump 'dump';
  # command to invoke kpsewhich
my $kpsewhich = "kpsewhich";
  # command to invoke kpsewhich for searching VF files
my $kpsewhich_vf = "kpsewhich -format=vf";

# globals
my ($src_main, $dst_main, @dst_base, $op_zrname, $op_zrtype);
my ($op_verb, $op_info, $op_zero, $op_force, $op_dryrun);
my ($op_overwr, $op_kpse);
my (%out_files);

#### main

sub main
{
  my ($vfc, $t, $fs, $fd, %tfm);
  read_option();
  my $vfc = parse_vf(read_whole(kpse_find("$src_main.vf")));
  if ($op_info) { info_vf($vfc); return; }
  if ($op_zrname) { set_names_zrname($vfc); }
  my $nb = scalar(@{$vfc->[0]}); my $nb1 = scalar(@dst_base);
  info("copy $src_main --> $dst_main");
  if ($nb == $nb1) { 
    info("source vf has $nb base tfm(s)");
  } else {
    w_error("wrong number of base tfm(s) (must be $nb)", $nb1);
    if ($nb1 > $nb) { $#dst_base = $nb - 1; }
  }
  write_whole("$dst_main.vf", form_vf($vfc));
  write_whole("$dst_main.tfm", read_whole(kpse_find("$src_main.tfm")));
  foreach my $k (0 .. $#dst_base) {
    my $sfn = $vfc->[0][$k][1]; my $dfn = $dst_base[$k];
    write_whole("$dfn.tfm", read_whole(kpse_find("$sfn.tfm")));
  }
  if ($op_dryrun) { return; }
  write_all();
}

#### vf parsing
use constant { FID_OVER => 999 };

sub parse_vf {
  my ($vf) = @_; my (@fs, @lst, $pos);
  @fs = unpack("CCC", $vf);
  ($fs[0] == 0xf7 && $fs[1] == 0xca) or return;
  $pos = $fs[2] + 11; my $hd = substr($vf, 0, $pos);
  while (1) {
    @fs = unpack("CC", substr($vf, $pos, 2));
    (243 <= $fs[0] && $fs[0] <= 246) or last;
    my $fid = ($fs[0] == 243) ? $fs[1] : FID_OVER;
    my $t = $fs[0] - 242 + 13;
    @fs = unpack("a${t}CC", substr($vf, $pos, 260));
    my $l = $fs[1] + $fs[2]; my $n = substr($vf, $pos + $t + 2, $l);
    $pos += $t + 2 + $l; push(@lst, [ $fs[0], $n, $fid ]);
    if ($n !~ m/^[\x21-\x7e]+$/) {
      $n =~ s/([^\x21-\x5b\x5d-\x7e])/sprintf("\\x%02x", ord($1))/g;
      error("bad tfm name recorded in VF", $n);
    }
  }
  my $ft = substr($vf, $pos); $ft =~ s/\xf8+\z//g;
  return [ \@lst, $hd, $ft ];
}

sub info_vf {
  my ($vfc) = @_;
  print("VF '$src_main' refers to:\n");
  foreach my $ent (@{$vfc->[0]}) {
    printf("%03d:%s\n", $ent->[2], $ent->[1]);
  }
}

sub form_vf {
  my ($vfc) = @_; my (@lst);
  if ($op_zero) {{
    my $t = $vfc->[0][0] or last;
    ($t->[2] == 0) and last; # already zero
    ($op_force || $t->[2] == 1)
      or w_error("first fontmap id is not 1", $t->[2]);
    info("change first fontmap id to zero (from " . $t->[2] . ")");
    substr($t->[0], 1, 1) = "\0"; $t->[2] = 0;
  }}
  foreach my $k (0 .. $#{$vfc->[0]}) {
    my $t = $vfc->[0][$k]; my $sfn = $t->[1];
    my $dfn = $dst_base[$k]; ($dfn ne '') or $dfn = $sfn;
    (length($dfn) < 256) or error("tfm name too long", $dfn);
    info(sprintf("(%03d) %s --> %s", $t->[2], $sfn, $dfn));
    push(@lst, $t->[0], "\0" . chr(length($dfn)), $dfn);
  }
  my $tfm = join('', $vfc->[1], @lst, $vfc->[2]);
  return $tfm . ("\xf8" x (4 - length($tfm) % 4));
}

## make-name

sub set_names_zrname {
  my ($vfc) = @_;
  my $fam = $dst_main; my $ent = $vfc->[0];
  $dst_main = new_name_zrname($src_main, $fam);
  foreach my $k (0 .. $#$ent) {
    $dst_base[$k] = new_name_zrname($ent->[$k][1], $fam);
  }
}

sub new_name_zrname {
  my ($name, $fam) = @_;
  {
    ($name =~ m/^[-\w]+$/) or last;
    my @fs = split(m/-/, $name);
    my $k = ($fs[0] eq 'r') ? 1 : 0; my $sfx = "";
    ($#fs >= $k + $#$fam) or last;
    if ($op_zrname == 2) { ($sfx) = ($fs[$k + 1] =~ m/([59]?)$/); }
    foreach (0 .. $#$fam) {
      $fs[$_ + $k] = $fam->[$_] . (($_ == 1) && $sfx);
    }
    return join('-', @fs);
  }
  error("name made in unexpected way", $name);
}

sub new_name_zrtype {
  my ($name, $typ) = @_; my ($pfx);
  ($name =~ m/^\w+-\w+$/)
    or error("bad target family/shape name", $name);
  if (my @fs = $typ =~ m/^([59])-(\w+)$/) {
    ($pfx, $typ) = @fs;
  } elsif ($typ !~ m/^\w+$/) {
    error("bad type name", $typ);
  }
  return "$name$pfx-$typ";
}

## input/output

sub read_whole {
  my ($fnam) = @_; my ($hin); local ($/);
  open($hin, '<', $fnam) && binmode($hin)
    or error("cannot open file for input", $fnam);
  info("read from", $fnam);
  my $buf = <$hin>; close($hin);
  return $buf;
}

sub write_whole {
  $out_files{$_[0]} = $_[1];
}

sub write_all {
  foreach my $fnam (sort(keys %out_files)) {
    if (!$op_overwr && file_exists($fnam)) {
      info("already exists", $fnam); next;
    }
    my $hout;
    open($hout, '>', $fnam) && binmode($hout)
      or error("cannot open file for output", $fnam);
    info("write to", $fnam);
    print $hout ($out_files{$fnam}); close($hout);
  }
}

  # check in same way as in Lua...
sub file_exists {
  open(my $hx, '<', $_[0]) or return;
  close($hx); return 1;
}

sub kpse_find {
  my ($fnam) = @_; my $out;
  my $cmd = ($fnam =~ m/\.vf$/i) ? $kpsewhich_vf : $kpsewhich;
  if ($op_kpse) {
    $out = `$cmd $fnam`; $out =~ s/\s+$//;
  } else {
    $out = (file_exists($fnam)) ? $fnam : '';
  }
  if ($out eq '') {
    if ($op_zrtype =~ m/z.$/) { # exit as normal
      info("source vf not found (it's ok)", $fnam); exit;
    } else { error("source vf not found", $fnam); }
  }
  if ($op_kpse) { info("file found by Kpathsearch", $fnam); }
  return $out;
}

## user interface

sub read_option {
  $op_verb = 0; $op_info = 0; $op_zero = 0; $op_force = 0;
  $op_overwr = 0; $op_zrname = 0; $op_kpse = 1;
  (@ARGV) or show_usage();
  while ($ARGV[0] =~ /^-/) {
    my $opt = shift(@ARGV); my $arg;
    if ($opt eq '-h' || $opt eq '--help') {
      show_usage();
    } elsif ($opt eq '-v' || $opt eq '--verbose') {
      $op_verb = 1;
    } elsif ($opt eq '-z' || $opt eq '--zero') {
      $op_zero = 1;
    } elsif ($opt eq '-f' || $opt eq '--force') {
      $op_force = 1;
    } elsif ($opt eq '-o' || $opt eq '--overwrite') {
      $op_overwr = 1;
    } elsif ($opt eq '-Z' || $opt eq '--zrname') {
      $op_zrname = 1;
    } elsif ($opt eq '-K' || $opt eq '--no-kpse') {
      $op_kpse = 0;
    } elsif ($opt eq '-D' || $opt eq '--dry-run') {
      $op_dryrun = 1; $op_verb = 1;
    } elsif ($opt eq '--zrname-x') {
      $op_zrname = 2;
    } elsif (($arg) = $opt =~ m/^--zrtype[:=]?(.*)/) {
      ($arg ne '') or error("argument is missing", $opt);
      $op_zrtype = $arg;
    } else {
      error("invalid option: $opt");
    }
  }
  ($src_main, $dst_main, @dst_base) = @ARGV;
  (defined $src_main) or error("no argument given");
  if (defined $op_zrtype) {
    $op_zrname = 2;
    $src_main = new_name_zrtype($src_main, $op_zrtype);
  }
  if (defined $dst_main) {
    if ($op_zrname) {
      (!@dst_base) or error("wrong number of arguments given");
      ($dst_main =~ m/^[-\w]+$/)
        or error("bad target family/shape name", $dst_main);
      $dst_main = [ split(m/-/, $dst_main) ];
    } elsif (!$op_force && !@dst_base) {
      error("no base tfm name given");
    }
  } else { $op_info = 1; }
}

sub show_usage{
  print <<"END"; exit;
This is $prog_name v$version <$mod_date> by 'ZR'.
Usage: $prog_name [<option>...] <in_font> <out_font> <out_base_tfm>...
       $prog_name [<option>...] <in_font>           (to show fontmap)
Arguments:
  <in_font>     input virtual font name (without path or extension)
    N.B. Input TFM/VF files are searched by Kpathsearch.
  <out_font>    output virtual font name
  <out_base_tfm>  names of raw TFMs referred by the output virtual font;
                each entry replaces a font mapping in the input font in
                the given order, so the exactly same number of entries
                must be given as font mappings
Options:
  -v --verbose  verbose mode
  -z --zero     change first fontmap id in vf from 1 to 0
  -f --force    ignore non-fatal errors
  -o --overwrite allow to overwrite existing files
  -Z --zrname   ZR-name mode; in this mode, <out_font> is given as family/
                variant name (leading subpart of font name following ZR-
                naming scheme) and <out_base_tfm> list must be empty; all
                output font names will be constructed automatically
  -K --no-kpse  disable Kpathsearch and assume all files stay in current
                directory
  -D --dry-run  turn on -v and do not write resulted files
END
}

sub message {
  print STDERR (join(": ", $prog_name, @_), "\n");
}

sub info { message(@_) if ($op_verb); }
sub alert { message("warning", @_); }
sub w_error { ($op_force) ? alert(@_) : error(@_); }
sub error {
  message(@_); unlink(keys %out_files); exit(-1);
}

#### go to main
main();
# EOF
