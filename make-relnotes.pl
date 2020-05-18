#
# Generate the release notes automatically in the style of 20.01 release notes



use Data::Dumper;

# what is the "previous baseline" tag
$base_tag = 'v20.05-rc0';

# the branch where we are making the release
$base_branch = 'stable/2005';

# the release for which we are making the release notes
$release_version = '20.05';

# previous release version
$prev_release_version = '20.01';


# make string ready to be used for RELEASE.md
sub mdstring {
	my $string = $_[0];
	# those that do not happen in the CLIs
	my $acronyms = [ 'vpp', 'sack', 'rtt', 'dpdk' ];
	foreach $my_acro (@{$acronyms}) {
		$string =~ s/\b$my_acro\b/uc($my_acro)/gex;
	}

	$string =~ s/^(\w)/\U$1/;
	# escape the '_' for markdown
	$string =~ s/([<>_])/\\$1/g;
	return $string;
}

sub print_commit_count {
	my $count = `git rev-list $base_tag..$base_branch | wc -l`;
	chomp($count);
	print("More than $count commits since the $prev_release_version release.\n");
}

# the command string passed as argument here should be something like:
# "git log --oneline --reverse --decorate=no --grep 'Type: component' v19.08.1..stable/1908"
#
sub collect_commits {
	my $cmd = $_[0];
	my $command_output = `$cmd`;
	my $out = {};
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		if ($aLine =~ /^([0-9a-fA-F]+) ([^:]+): (.+)$/) {
			my $aCommitID = $1;
			my @aComponents = split(' ', $2);
			my $aComponent = $aComponents[0];
			my $aComment = $3;
			if (!exists($out->{$aComponent})) {
				$out->{$aComponent} = [];
			}
			my $aEntry = { 'commit_id' => $aCommitID, 'comment' => $aComment, 'comment_r' => mdstring($aComment) };
			push(@{$out->{$aComponent}}, $aEntry);
		}
	}
	return $out;
}



# 
# Read the maintainers file into a hash, indexed by short component name,
# for now just reads short name and long name.
#
sub read_maintainers() {
	open(F, "MAINTAINERS") || die("Could not open MAINTAINERS file");
	my $short_name = "";
	my $long_name = "";
	my $in_component = 0;
	my $out = {};
	while (<F>) {
		chomp();
		my $aLine = $_;
		# print ("LINE: $aLine\n");
		if (/^([A-Z]):\s+(.*)$/) {
			my $aLetter = $1;
			my $aValue = $2;
			# print ("LETTER: $aLetter, VALUE: $aValue\n");
			if ($aLetter eq "I") {
				$short_name = $aValue;
			}
			# FIXME: deal with all the other letters here
		} elsif (/^(\s*)$/) {
			if ($in_component) {
				$in_component = 0;
				if ($short_name ne "") {
					my $comp = {};
					$comp->{'short_name'} = $short_name;
					$comp->{'name'} = $long_name;
					$out->{$short_name} = $comp;
					# print("FEATURE: $short_name => $long_name\n");
					$short_name = "";
					$long_name = "";
				}
			}
			# print ("END\n");
		} elsif (/^([^\s].*)$/) {
			$in_component = 1;
			$long_name = $1;
		}
	}
	return($out);
}


# print the markdown version of the release notes generated based on the components hash
# and the commits-per-component hash
sub print_markdown {
	my $components = $_[0];
	my $commits = $_[1];
	my $base_indent = $_[2];

	# section prefixes to group the components into
	my $section_prefixes = { "VNET " => "VNET", "Plugin - " => "Plugins" };

	# Sort the component list by alphabetical order of the human-friendly component name
	my @componentlist = sort({$components->{$a}->{'name'} cmp $components->{$b}->{'name'}} keys(%{$components}));

	my @result = map { "$_: $components->{$_}->{'name'}" } @componentlist;
	# print Dumper(\@componentlist);

	# print Dumper(\@result);
	# print Dumper($commits);

	my $indent = $base_indent;
	my $in_section = 0;
	my $section_prefix = "";

	foreach $aFeature (@componentlist) {
		my $component_name = $components->{$aFeature}->{'name'};
		if ($in_section) {
			if (rindex($component_name, $section_prefix, 0) != 0) {
				$in_section = 0;
				$section_prefix = "";
				$indent = $base_indent;
			}

		}
		if (length($commits->{$aFeature}) == 0) {
			next;
		}
		# the "in_section" might have been just reset, so need another branch
		if (!$in_section)	{
			foreach $aPrefix (keys %{$section_prefixes}) {
				if (rindex($component_name, $aPrefix, 0) == 0) {
					$in_section = 1;
					$section_prefix = $aPrefix;
					my $section_name = $section_prefixes->{$aPrefix};
					print("$indent- $section_name\n");
					$indent = "$base_indent  ";
					break;
				}
			}
		}
		if ($in_section) {
			$component_name =~ s/^$section_prefix//g;
		}
		$component_name = mdstring($component_name);
		print("$indent- $component_name\n");
		foreach $aCommit (@{$commits->{$aFeature}}) {
			# print(Dumper($aCommit));
			my $msg = $aCommit->{'comment_r'};
			my $cid = $aCommit->{'commit_id'};
			my $aOutLine = "$msg ($cid)";
			print("$indent  - $aOutLine\n");
		}
	}
}

sub get_api_changes {
	my $base_tag_branch = "$base_branch-api-baseline";
	$base_tag_branch =~ s/\//-/g;
	`git checkout master`;
	`git branch -d $base_tag_branch`;
	`git checkout -b $base_tag_branch $base_tag`;
	`make install-dep`;
	`git clean -fdx`;
	print STDERR "Building base versio for API changesn\n";
	`make build`;
	`sudo rm /tmp/api-table.$base_tag_branch`;
	`sudo ./build-root/install-vpp_debug-native/vpp/bin/vpp api-trace { on save-api-table api-table.$base_tag_branch } unix { cli-listen /run/vpp/api-cli.sock }`;

	`git checkout $base_branch`;
	print STDERR "Building current version for API changesn\n";
	`git branch -d $base_tag_branch`;
	`make install-dep`;
	system("sudo pkill vpp");
	`git clean -fdx`;
	`make build`;

	`sudo ./build-root/install-vpp_debug-native/vpp/bin/vpp api-trace { on } unix { cli-listen /run/vpp/api-cli.sock }`;
	sleep(30);
	$api_changes = `sudo ./build-root/install-vpp_debug-native/vpp/bin/vppctl -s /run/vpp/api-cli.sock show api dump file /tmp/api-table.$base_tag_branch compare`;
	system("sudo pkill vpp");

	return($api_changes);
}

sub print_api_change_commits {
	print "### Patches that changed API definitions\n\n";
	my $emit_md = 1;
	my $command_output = `find . -name '*.api' -print`;
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		$aLine =~ s#^\.\/##g;
		my $command_output = `git log --oneline $base_tag..$base_branch $aLine`;
		if ($command_output eq "") {
			next;
		}
		if ($emit_md) {
			print("| \@c $aLine ||\n");
			foreach $aLine (split(/[\r\n]+/, $command_output)) {
				my @parts = split(/\s+/,$aLine);
				my $commit = shift(@parts);
				my $message = join(" ", @parts);
				$message =~ s/\|/\\|/g;
				print("| [$commit](https://gerrit.fd.io/r/gitweb?p=vpp.git;a=commit;h=$commit) | $message |\n");
			}
			print("\n");
		} else {
			print("$aLine\n");
			print("$command_output\n");
		}
	}
}

sub print_feature_change_commits {
	print "### Patches that changed FEATURE.yaml definitions\n\n";
	my $emit_md = 1;
	my $command_output = `find . -name 'FEATURE.yaml' -print`;
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		$aLine =~ s#^\.\/##g;
		my $file_name = $aLine;
		my $command_output = `git log --oneline $base_tag..$base_branch $aLine`;
		if ($command_output eq "") {
			next;
		}
		if ($emit_md) {
			print("| \@c $aLine ||\n");
			foreach $aLine (split(/[\r\n]+/, $command_output)) {
				my @parts = split(/\s+/,$aLine);
				my $commit = shift(@parts);
				my $message = join(" ", @parts);
				$message =~ s/\|/\\|/g;
				print("| [$commit](https://gerrit.fd.io/r/gitweb?p=vpp.git;a=commit;h=$commit) | $message |\n");
				my $command_output = `git diff $commit~1..$commit $file_name`;
				print("```\n$command_output\n```\n");
			}
			print("\n");
		} else {
			print("$aLine\n");
			print("$command_output\n");
		}
	}
}


sub print_release_note {

	my $api_changes = get_api_changes();
	my $page_id = "release_notes_$release_version";
	$page_id =~ s/\.//g;

        print("\@page $page_id Release notes for VPP $release_version\n\n");
	print_commit_count();

	my $the_header = <<__E__;

## Release Highlights

REPLACE AS NEEDED
The $release_version is an LTS release. It contains numerous fixes,
as well as new features and API additions.

## Features

__E__
        print($the_header);

	my $components = read_maintainers();
	my $commits = collect_commits("git log --oneline --reverse --decorate=no --grep 'Type: feature' $base_tag..$base_branch");
	# my $commits = collect_commits("git log --oneline --reverse --decorate=no --grep 'VPP-' v19.08.1..stable/1908");

	print_markdown($components, $commits);

	my $trailer = <<__E__;

## Known issues

For the full list of issues please refer to fd.io [JIRA](https://jira.fd.io).

## Fixed issues

For the full list of fixed issues please refer to:
- fd.io [JIRA](https://jira.fd.io)
- git [commit log](https://git.fd.io/vpp/log/?h=$base_branch)

__E__

	print($trailer);

	my $api_changes_header = <<__E__;

## API changes

Description of results:

* _Definition changed_: indicates that the API file was modified between releases.
* _Only in image_: indicates the API is new for this release.
* _Only in file_: indicates the API has been removed in this release.

__E__

	print($api_changes_header);
	print("$api_changes\n");
        print_api_change_commits();

}


#
# FIXME: generate the data as a string rather than printing it.
#
# And commit
#
#    git commit -a -s --amend -m "misc: 19.08.2 Release Notes
#
# Type: docs
# "

print_release_note();

