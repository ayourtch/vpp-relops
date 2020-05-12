#!/bin/perl
#
# Screen-scrape jenkins job status, correlated with nomad status, put into sqlite database
#


sub curl_get_all_jobs_sql {
	my $jobname = $_[0];
	my $command_output = `curl https://jenkins.fd.io/job/${jobname}/`;
	my $ret = "";
	my $now = time();
	sleep(3);

	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		if ($aLine =~ /\#(\d+)/ ) {
			my $job_number = $1;
			my $job_status = "unknown";
			my $job_completed = 0;
			if ($aLine =~ /red\./) {
				$job_status = "failed";
				$job_completed = 1;
			} elsif ($aLine =~ /blue\./) {
				$job_status = "success";
				$job_completed = 1;
			};
			if ($job_completed) {
				$ret = $ret . "INSERT INTO JenkinsJobs VALUES('$jobname/$job_number', '$jobname', $job_number, '$job_status', $now, '');\n";
			}
		}
	}
	return ($ret);
}

sub curl_get_executor_name {
	my $job_id= $_[0];
	my $url = "https://jenkins.fd.io/view/vpp/job/${job_id}/";
	print("FETCH: $url\n");
	sleep(15);
	my $command_output = `curl $url`;
	my $executor_name = "";
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		if ($aLine =~ /            on ([^<]+)/) {
			$executor_name = $1;
		}
	}
	return ($executor_name);
}

sub run_sql {
	my $sql = $_[0];
	print("RUN SQL: $sql\n");
	open(DBPIPE, "| sqlite3 jobmonitor.sqlite3") || die ("Could not open db");
	print DBPIPE $sql;
	close(DBPIPE);
}

# this is SQLI-heaven, for the case where the inputs are not trusted... kids, do not do it! :)
sub get_sql_data {
	my $sql = $_[0];
	$ret = `sqlite3 jobmonitor.sqlite3 '$sql'`;
	return ($ret);
}

sub ensure_db() {
	my $sql = <<__EE__;

CREATE TABLE JenkinsJobs (
   JenkinsJobID nvarchar(100) NOT NULL PRIMARY KEY,
   JobName nvarchar(100) NOT NULL,
   JobNumber INTEGER NOT NULL,
   JobStatus nvarchar(30) NOT NULL,
   AddedAt INTEGER NOT NULL,
   JenkinsExecutor nvarchar(100) NOT NULL
);

CREATE TABLE JenkinsExecutors (
	JenkinsExecutorID nvarchar(100) NOT NULL PRIMARY KEY,
	AddedAt INTEGER NOT NULL,
	NomadQueried INTEGER NOT NULL,
	NomadAllocID nvarchar(100) NOT NULL,
	NomadNodeID nvarchar(100) NOT NULL
);

CREATE TABLE NomadJobStatuses (
	NomadJobID nvarchar(100),
	AddedAt INTEGER NOT NULL,
	QueryData nvarchar(32000) NOT NULL
);

CREATE TABLE NomadAllocs (
	NomadAllocID nvarchar(100) NOT NULL PRIMARY KEY,
	NomadNodeID nvarchar(100) NOT NULL,
	NomadJobID nvarchar(100) NOT NULL,
	AddedAt INTEGER NOT NULL,
	NomadQueried INTEGER NOT NULL
);

CREATE TABLE NomadAllocStatuses (
	NomadAllocID nvarchar(100),
	AddedAt INTEGER NOT NULL,
	QueryData nvarchar(32000) NOT NULL
);


__EE__

	if (! -f "jobmonitor.sqlite3") {
		run_sql($sql);
	}

}

my $x = <<_EE_;
ID            = prod-amd-4337f50615596
Name          = prod-amd-4337f50615596
Submit Date   = 2020-05-12T11:25:28Z
Type          = batch
Priority      = 50
Datacenters   = yul1
Status        = dead (stopped)
Periodic      = false
Parameterized = false

Summary
Task Group               Queued  Starting  Running  Failed  Complete  Lost
jenkins-slave-taskgroup  0       0         0        0       1         0

Allocations
ID        Node ID   Task Group               Version  Desired  Status    Created    Modified
a1b339ae  c622286a  jenkins-slave-taskgroup  0        stop     complete  1h54m ago  1h7m ago
_EE_

sub cli_check_alloc {
	my $alloc_id = $_[0];
	my $command_output = `nomad status $alloc_id`;
	my $now = time();
	my $sql = "";
	run_sql("INSERT INTO NomadAllocStatuses VALUES('$alloc_id', $now, '$command_output');\n");
	run_sql("UPDATE NomadAllocs SET NomadQueried=1 WHERE NomadAllocID='$alloc_id';\n");
}

sub cli_check_executor {
	my $executor_name = $_[0];
	my $command_output = `nomad status $executor_name`;
	my $now = time();
	run_sql("INSERT INTO NomadJobStatuses VALUES('$executor_name', $now, '$command_output');\n");
	my $sql = "";

	$sql = $sql . "UPDATE JenkinsExecutors SET NomadQueried=1 WHERE JenkinsExecutorID='$executor_name';\n";

	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		if($aLine =~ /^([0-9a-f]+)\s+([0-9a-f]+)\s+/) {
			my $alloc_id = $1;
			my $node_id = $2;
			$sql = $sql . "UPDATE JenkinsExecutors SET NomadQueried=1, NomadAllocID='$alloc_id',NomadNodeID='$node_id' WHERE JenkinsExecutorID='$executor_name';\n";
			$sql = $sql . "INSERT INTO NomadAllocs VALUES('$alloc_id', '$node_id', '$executor_name', $now, 0);\n";
		}
	}
	run_sql($sql);

	$command_output = get_sql_data("SELECT NomadAllocID FROM NomadAllocs WHERE NomadQueried=0 ORDER BY AddedAt DESC LIMIT 30;");
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		print("AllocID: $aLine\n");
		cli_check_alloc($aLine);
	}
}

sub update_job_data {
	my $job_name = $_[0];

	my $now = time();
	my $sql = curl_get_all_jobs_sql($job_name);

	# inserts for the jobs that are already there will fail - which is what we want...
	run_sql($sql);

	# $command_output = get_sql_data("SELECT JenkinsJobID FROM JenkinsJobs WHERE JenkinsExecutor=\"\" ORDER BY JobNumber DESC LIMIT 1;");
	$command_output = get_sql_data("SELECT JenkinsJobID FROM JenkinsJobs WHERE JenkinsExecutor=\"\" AND AddedAt >= $now LIMIT 10;");

	my $sql = "";

	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		print("JOB: $aLine\n");

		my $executor_name = curl_get_executor_name($aLine);
	
		if ($executor_name ne "") {
			$sql = $sql . "UPDATE JenkinsJobs SET JenkinsExecutor=\"$executor_name\" WHERE JenkinsJobID=\"$aLine\";\n";
			$sql = $sql . "INSERT INTO JenkinsExecutors VALUES('$executor_name', $now, 0, '', '');\n";
		}
	}
	run_sql($sql);


	$command_output = get_sql_data("SELECT JenkinsExecutorID FROM JenkinsExecutors WHERE NomadQueried=0 LIMIT 30;");
	foreach $aLine (split(/[\r\n]+/, $command_output)) {
		print("EXECUTOR: $aLine\n");
		cli_check_executor($aLine);
	}
}


ensure_db();
my $job_name = "vpp-verify-master-clang";
update_job_data($job_name);
my $job_name = "vpp-verify-master-ubuntu1804";
update_job_data($job_name);
my $job_name = "vpp-verify-master-centos7";
update_job_data($job_name);
my $job_name = "vpp-merge-master-centos7";
update_job_data($job_name);
