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
	my $relnote_source = "branch $branch";
	if ($branch =~ /^FILE:(.*)$/) {
		my $filename = $1;
		open(F, "$filename") || die("Could not open file $filename");
		$relnote_source = "file $filename";
	} else {
		open(F, "git show $branch:RELEASE.md |") || die("Could not open RELEASE.md file in branch $branch");
	}
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
				print STDERR "    Added page $curr_page from $relnote_source\n";
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
		print STDERR "    Added page $curr_page from $relnote_source\n";
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
print STDERR "Target branch: $target_branch\n";
my $target_pages = read_relnotes($target_branch);
# print Dumper($target_pages);
while (my $aBranch = shift) {
	print STDERR "  Merge from branch: $aBranch\n";
	if ($aBranch =~ /^TBD:(\d\d)\.(\d\d)$/) {
		my $VerMajor = $1;
		my $VerMinor = $2;
		my $aData = "\nTBD\n\n";
		my $p = "release_notes_$VerMajor$VerMinor";
		my $aTitle = "Release notes for VPP $VerMajor.$VerMinor";
		$target_pages->{$p} = { "data" => $aData, 'title' => $aTitle };
		continue;
	}
	my $some_pages = read_relnotes($aBranch);
	# print Dumper($some_pages);
	foreach my $p (keys(%{$some_pages})) {
		if (!exists($target_pages->{$p})) {
			print STDERR "Adding page $p from branch $aBranch\n";
			$target_pages->{$p} = $some_pages->{$p};
		} else {
			if ($target_pages->{$p}->{'data'} =~ /^\s*TBD\s*$/sm) {
				print STDERR "Replacing TBD with page $p from branch $aBranch\n";
				$target_pages->{$p} = $some_pages->{$p};
			}
		}
	}
}

print_pages($target_pages);




