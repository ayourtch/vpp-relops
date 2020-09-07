#!/usr/bin/perl
#
use strict;
use warnings;
use 5.010;

use Data::Dumper;

# merge the RELEASE.md from other branches
# syntax: 

# perl relnote-sync.pl <target-branch> <source-branch> <source-branch> ...

sub read_relnotes {
	my $branch = $_[0];
	open(F, "git show $branch:RELEASE.md |") || die("Could not open RELEASE.md file");
	my $curr_page = "";
	my $curr_page_data = "";
	my $curr_page_title = "";
	my $pages = {};
        while (<F>) {
		chomp();
		my $aLine = $_;
		# print("L:$aLine\n");
		if ($aLine =~ /^\@page\s(\S+)\s(.*?)$/) {
			my $aPage = $1;
			my $aTitle = $2;
			if ($curr_page ne "") {
				$pages->{$curr_page} = { "data" => $curr_page_data, "title" => $curr_page_title };
			}
			$curr_page = $aPage;
			$curr_page_title = $aTitle;
			$curr_page_data = "";
		} else {
			$curr_page_data = $curr_page_data . "$aLine\n";
		}
	}
	if ($curr_page ne "") {
		$pages->{$curr_page} = { "data" => $curr_page_data, "title" => $curr_page_title };
	}
	close(F);
	return $pages;
}


sub print_pages {
	my $pages = $_[0];
	my $page_keys = [];
	foreach my $p (keys(%{$pages})) {
		push(@{$page_keys}, $p);
	}
	@{$page_keys} = reverse(sort(@{$page_keys}));
	print("# Release Notes    {#release_notes}\n\n");
	foreach my $p (@{$page_keys}) {
		print("* \@subpage $p\n");
	}
	print("\n");
	foreach my $p (@{$page_keys}) {
		my $aTitle = $pages->{$p}->{'title'};
		my $aData = $pages->{$p}->{'data'};
		print("\@page $p $aTitle\n");
		print($aData);
	}
}

my $target_branch = shift || die "Need a target branch for RELEASE.md";
my $target_pages = read_relnotes($target_branch);
# print Dumper($target_pages);
while (my $aBranch = shift) {
	print STDERR "target branch: $aBranch\n";
	my $some_pages = read_relnotes($aBranch);
	# print Dumper($some_pages);
	foreach my $p (keys(%{$some_pages})) {
		if (!exists($target_pages->{$p})) {
			print STDERR "Adding page $p from branch $aBranch\n";
			$target_pages->{$p} = $some_pages->{$p};
		}
	}
}

print_pages($target_pages);




