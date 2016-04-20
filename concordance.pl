#!/usr/bin/perl

use strict;

#close STDIN;

my $print_header=0;

my $knob_x = ($ARGV[0] || die "provide knob_x");
my $knob_y = ($ARGV[1] || die "provide knob_x");


my @x;
push @x, $knob_x;
$x[-1] .= ":X0" if $x[-1] !~ /:/;

my @y;
push @y, $knob_y;
$y[-1] .= ":Y0" if $y[-1] !~ /:/;

if ($print_header) {
  print "#$knob_x\n#$knob_y\n";
  print "#score,yeslink,nolink,nclink\n";
}

#print "<TABLE>";
my @xlists;

#print "<TR><TH></TH>\n";
for my $xfile (@x) {
  #printf "<TH><code>%8.8s</code></TH>\n", unique_part( $xfile, @x );
  push @xlists, &readsnplist($xfile);
}

#print( "<!--\n", ( map { "x $_\n" } @x ), ( map { "y $_\n" } @y ), "-->\n" );
my @xhash = map { readlink($_) =~ /([0-9a-f]{32})/ || /([0-9a-f]{32})/ } @x;
my @yhash = map { readlink($_) =~ /([0-9a-f]{32})/ || /([0-9a-f]{32})/ } @y;
#my @snpcounts;

#print "</TR>\n";
for my $yfile (@y) {

  #printf "<TR><TH><CODE>%8.8s</CODE></TH>\n", unique_part( $yfile, @y );

  my $ylist_orig = &readsnplist($yfile);
  my $yhash      = shift @yhash;
  my @xscore;
  my $xhighscore = 0;

  for ( my $xi = 0 ; $xi <= $#xlists ; $xi++ ) {
    my $xlist_orig = $xlists[$xi];

    my $xlist          = [@$xlist_orig];
    my $ylist          = [@$ylist_orig];
    my $score_nocall_x = 0;
    my $score_nocall_y = 0;
    my $score_yes      = 0;
    my $score_no       = 0;

    while ( @$xlist && @$ylist ) {

      my $cmp = $xlist->[0]->[0] cmp $ylist->[0]->[0]
        || $xlist->[0]->[1] <=> $ylist->[0]->[1];

      if ( $cmp < 0 )    { shift @$xlist; }
      elsif ( $cmp > 0 ) { shift @$ylist; }

      else {
        # same position
        my $nocall_x = $xlist->[0]->[2] =~ /^[NX]/;
        my $nocall_y = $ylist->[0]->[2] =~ /^[NX]/;
        if ( $nocall_x && !$nocall_y ) {
          ++$score_nocall_x;
        }
        elsif ( !$nocall_x && $nocall_y ) {
          ++$score_nocall_y;
        }
        elsif ( $nocall_x && $nocall_y ) {
        }
        elsif ( $xlist->[0]->[2] eq $ylist->[0]->[2] ) {
          ++$score_yes;
        }
        else {
          ++$score_no;
        }
        shift @$xlist;
        shift @$ylist;
      }

    }

    my $score =
      ( $score_yes + $score_no )
      ? 100 * $score_yes / ( $score_yes + $score_no )
      : "-";

    push @xscore,
      [ $score, $score_yes, $score_no, $score_nocall_x, $score_nocall_y ];
    $xhighscore = $score if $xhighscore < $score;

  }

  for ( my $xi = 0 ; $xi <= $#xscore ; $xi++ ) {

    my $score   = $xscore[$xi]->[0];
    my $star    = $score > $xhighscore * .9;
    my $redness = ( $score - 60 ) * 128 / 40;
    $redness = 0 if $redness < 0;
    #my $color = sprintf( "#ff%02x%02x", 255 - $redness, 255 - $redness );

    #printf "<TD style=\"background: $color\">%.0f%s</TD>", $xscore[$xi]->[0],
    #  $star ? "*" : "";

    printf "%.0f", $xscore[$xi]->[0];

    if ( $star || ( $xhighscore == 0 && $xi == 0 ) ) {
      my $xhash = $xhash[$xi];
      my $label = sprintf(
        "<code>%8.8s / %8.8s</code>",
        &unique_part( $yfile,  @y ),
        &unique_part( $x[$xi], @x )
      );
      my ( $x, $yes, $no, $nocallx, $nocally ) = @{ $xscore[$xi] };
      my $yeslink = snpdig_link( "$yhash;agree-$xhash",       $yes );
      my $nolink  = snpdig_link( "$yhash;disagree-$xhash",    $no );
      my $nclink  = snpdig_link( "nocall-$yhash;call-$xhash", $nocally );
      #push @snpcounts, qq{<TR><TH>$label</TH><TD>$yeslink</TD><TD>$nolink</TD><TD>$nclink</TD></TR>\n};
      #push @snpcounts, qq{<!-- $yhash $xhash $yes $no $nocally -->\n};

      print ",$yeslink,$nolink,$nclink";
    } else {
      print ",,,";
    }

    print "\n";

  }

  #print "</TR>\n";

}

#print "</TABLE>\n";
#unshift @snpcounts, qq{<TR><TD><u>high scoring pair (y/x)</u></TD><TD><u>concordant</u></TD><TD><u>discordant</u></TD><TD><u>nocall_y:call_x</u></TD></TR>\n};
#print "<TABLE>", @snpcounts, "</TABLE>";

close STDOUT or die "writer exited $?";

sub readsnplist {

  my $file = shift;
  $file =~ s/:.*//;
  if ( $file =~ /^[0-9a-f]{32}/ && !-e $file ) {
    warn "$file: gzip -cdf\n" if $ENV{DEBUG};
    #open STDIN, "-|", "gzip -cdf $file"
    open FH, "-|", "gzip -cdf $file"
      or die "gzip -cdf: $!";
  }

  else {
    warn "$file: open\n" if $ENV{DEBUG};
    #open STDIN, "-|", "gzip", "-cdf", $file or die "$file: $!";
    open FH, "-|", "gzip", "-cdf", $file or die "$file: $!";
  }

  my @snplist;
  #while (<STDIN>) {
  while (<FH>) {

    chomp;

    my @fields = split( /\t/, $_, 9 );

    ## VCF?
    ##
    if ( $fields[1] =~ /^\d+$/ && $fields[2] =~ /^.$/ ) {
      my ( $chr, $pos, $refbp, $seqbp, $extra ) = @fields;
      push @snplist, [ $chr, $pos, fasta2bin($seqbp) ];
    }

    ## VCF...
    ##
    #if ( $fields[1] =~ /^\d+$/ && $fields[3] =~ /^.$/ && $fields[4] =~ /^.$/ ) {
    #  my ( $chr, $pos, $id, $refbp, $seqbp, $extra ) = @fields;
    #  push @snplist, [ $chr, $pos, fasta2bin($seqbp) ];
    #}

    ## GFF
    ## fourth field is start position and equals end position (that is,
    ## it's a snp) and there's an 'alleles' entry.
    ##
    elsif ( $fields[3] =~ /^\d+$/
      && $fields[4] == $fields[3]
      && $fields[8] =~ /alleles ([A-Z\/]+)\b/i )
    {

      my ( $chr, $pos, $seqbp ) = ( @fields[ 0, 3 ], $1 );
      next unless $seqbp =~ /^[A-Z](\/[A-Z])?$/i;

      if ( $ENV{'KNOB_RSID_ONLY'} ) {
        while ( $fields[8] =~ /[:,]rs(\d+)/g ) {
          push @snplist, [ 'rs', $1, fasta2bin($seqbp) ];
        }
      }

      else {
        push @snplist, [ $chr, $pos, fasta2bin($seqbp) ];
      }

    }

    ## Genotype...
    ##
    elsif ( $ENV{'KNOB_RSID_ONLY'}
      && $fields[2] =~ /^[ACGT]$/
      && $fields[3] =~ /^[ACGT]$/
      && $fields[0] =~ /^rs(\d+)/ )
    {
      # immunochip
      my ( $chr, $pos, $seqbp ) = ( 'rs', $1, $fields[2] . $fields[3] );
      push @snplist, [ $chr, $pos, fasta2bin($seqbp) ];
    }

  }

  #close STDIN or die "input: $!";
  close FH or die "input: $!";
  warn "$file: \$#snplist == $#snplist\n" if $ENV{DEBUG};
  return [ sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] } @snplist ];

}

# XACMGRSVTWYHKDBN
# 0123456789abcdef
#
# return 'N' if it starts with 'N'
# return 'X' if it's 'X'
# otherwise:
#   - capitalize entries
#   - remove any non alphabetical entries
#   - does the mapping above
#   - peels off lower 4 bits until none are left,
#     keeping a running OR result
#
# under 'normal' cases (a snp with 1 or 2 base pairs)
# the value returned willbe an 4 bit integer with
# a bit set for each 'a', 'c', 'g' or 't' found.
#
sub fasta2bin {
  my $fasta = shift;
  return "N" if $fasta =~ /^N/;
  return "X" if $fasta eq "X";
  $fasta =~ tr/a-z/A-Z/;
  $fasta =~ s/[^A-Z]//g;
  $fasta =~ tr/XACMGRSVTWYHKDBN/0123456789abcdef/;
  $fasta = hex($fasta);
  while ( $fasta & ~0xf ) {
    $fasta = ( $fasta & 0xf ) | ( $fasta >> 4 );
  }
  return $fasta;
}

sub unique_part {
  @_ = @_;
  for (@_) { s/^.*?:(.)/$1/ || s/://; s/[\r\n]//g; }
  my $this    = shift;
  my $thislen = length($this);
  my $ustart  = $thislen;
  my $uend    = $thislen;
  for (@_) {
    $ustart-- while substr( $this, 0, $ustart ) ne substr( $_, 0, $ustart );
    $uend--
      while $uend
      && substr( $this, $thislen - $uend ) ne substr( $_, length($_) - $uend );
  }
  $ustart = 0 if $ustart <= 3;
  return substr( $this, $ustart, $thislen - $uend - $ustart );
}

sub snpdig_link {
  my $pathinfo = shift;
  my $label    = shift;
  return $label if !exists $ENV{"KNOB_SNPDIGURL"};
  return "<a href=\"" . $ENV{"KNOB_SNPDIGURL"} . "/$pathinfo\">$label</a>";
}
