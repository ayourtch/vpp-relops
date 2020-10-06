#
# Generate the release notes automatically in the style of 20.01 release notes



use Data::Dumper;
use Env;
use Env qw(VPP_CHECK_API);

sub get_next_vpp_version {
	my $base_tag = $_[0];
	if ($base_tag =~ /v(\d+\.\d+)-rc0/) {
		return $1;
	}
	if ($base_tag =~ /v(\d+\.\d+)-rc[12]/) {
		return $1;
	}
	die "Base tag $base_tag not handled yet!";
}

sub get_base_tag {
	my $base_tag_raw = $_[0];
	if ($base_tag_raw =~ /v(\d+\.\d+)-rc[012]/) {
		return "v$1-rc0";
	}
	die "Base tag $base_tag not handled yet!";
}

# what is the "previous baseline" tag
# $base_tag = 'v20.05-rc0';

$sed_cmd = 's/-[^-]\+-[^-]\+$//g';
$base_tag_raw = `git describe --long HEAD | sed -e '$sed_cmd'`;
chomp($base_tag_raw);

$base_tag = get_base_tag($base_tag_raw);

if ($base_tag eq "") {
	die("Empty base tag!");
}

# the branch where we are making the release
# $base_branch = 'stable/2005';
$base_branch = `git rev-parse --abbrev-ref HEAD`;
chomp($base_branch);


# the release for which we are making the release notes
# $release_version = '20.05';
$release_version = get_next_vpp_version($base_tag);

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
	my $count_fix = `git rev-list --grep 'Type: fix' $base_tag..$base_branch | wc -l`;
	chomp($count_fix);
	print("More than $count commits since the previous release, including $count_fix fixes.\n");
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
			my $aOutLine = "$msg ([$cid](https://gerrit.fd.io/r/gitweb?p=vpp.git;a=commit;h=$cid))";
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
	print STDERR "Building base version for API changes\n";
	`make build >&2`;
	`rm -f /tmp/api-table.$base_tag_branch`;
	print STDERR "Collecting the table of old APIs from running VPP\n";
	`./build-root/install-vpp_debug-native/vpp/bin/vpp api-trace { on save-api-table api-table.$base_tag_branch } unix { cli-listen /tmp/vpp-api-cli.sock }`;
	print STDERR `ls -al /tmp/api-table.$base_tag_branch`;
	print STDERR "Checking out branch $base_branch";

	`git checkout $base_branch`;
	print STDERR "Building current version for API changesn\n";
	`git branch -d $base_tag_branch`;
	`make install-dep`;
	print STDERR "Stopping VPP\n";
	`pkill vpp`;
	print STDERR "Cleaning up and rebuilding VPP\n";
	`git clean -fdx`;
	`make build >&2`;

	`./build-root/install-vpp_debug-native/vpp/bin/vpp api-trace { on } unix { cli-listen /tmp/vpp-api-cli.sock } >&2`;
	print STDERR "Sleep for 30 sec to let VPP come up\n";
	sleep(30);
	$api_changes = `./build-root/install-vpp_debug-native/vpp/bin/vppctl -s /tmp/vpp-api-cli.sock show api dump file /tmp/api-table.$base_tag_branch compare`;
	print STDERR `ps -ef | grep vpp`;
	print STDERR "Stopping VPP\n";
	`pkill vpp`;

	# remove the ms-dos linefeeds
	$api_changes =~ s/\r//gsm;

	return($api_changes);
}

sub get_api_process_changes {
	my $api_changes = `./extras/scripts/crcchecker.py --git-revision $base_tag | egrep -e 'deprecated:|in-progress:'`;
	my @in_progress_apis;
	my @deprecated_apis;
	foreach my $aLine (split(/[\r\n]+/, $api_changes)) {
		my @parts = split(/[: ]+/, $aLine);
		if ($parts[0] =~ /deprecated/) {
			push(@deprecated_apis, $parts[1]);
		} elsif ($parts[0] =~ /in-progress/) {
			push(@in_progress_apis, $parts[1]);
		}
	}
	@deprecated_apis = sort(@deprecated_apis);
	@in_progress_apis = sort(@in_progress_apis);
	my $result = { "deprecated" => \@deprecated_apis, "in_progress" => \@in_progress_apis };
	# print Dumper($result);
	return $result;
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
			print("| ------- | ------- |\n");
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
	print("\n");
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

sub print_api_process_changes {
	my $api_process_changes = get_api_process_changes();

	my $api_deprecated_header = <<__E__;

### Newly deprecated API messages

These messages are still there in the API, but can and probably
will disappear in the next release.

__E__
	my $api_in_progress_header = <<__E__;

### In-progress API messages

These messages are provided for testing and experimentation only.
They are *not* subject to any compatibility process,
and therefore can arbitrarily change or disappear at *any* moment.
Also they may have less than satisfactory testing, making
them unsuitable for other use than the technology preview.
If you are intending to use these messages in production projects,
please collaborate with the feature maintainer on their productization.

__E__


	print($api_deprecated_header);
	foreach my $m (@{$api_process_changes->{'deprecated'}}) {
		print("- $m\n");
	}
	print($api_in_progress_header);
	foreach my $m (@{$api_process_changes->{'in_progress'}}) {
		print("- $m\n");
	}
	print("\n");
}


sub print_api_changes {
	my $api_changes = get_api_changes();

	my $api_changes_header = <<__E__;

## API changes

Description of results:

* _Definition changed_: indicates that the API file was modified between releases.
* _Only in image_: indicates the API is new for this release.
* _Only in file_: indicates the API has been removed in this release.

__E__

	print($api_changes_header);
	print("$api_changes\n");
}


sub print_release_note {

	my $page_id = "release_notes_$release_version";
	$page_id =~ s/\.//g;

	print("\@page $page_id Release notes for VPP $release_version\n\n");
	print_commit_count();

	my $date_now = `date`;
	chomp($date_now);

	my $the_header = <<__E__;

## Release Highlights

These are the *DRAFT* release notes for the upcoming VPP $release_version release, generated as on $date_now.

HIGHLIGHTS-PLACEHOLDER

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
if ($VPP_CHECK_API) {
  print_api_changes();
}
print_api_process_changes();
print_api_change_commits();
