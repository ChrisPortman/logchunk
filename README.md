# LogChunk

## CURRENT STATUS

I've so far spent a total of 1 day on this between entertaining a 2 year old.  It's maturity is about on par with that 2 year old but way less cute.

## Overview

Logchunk is an attempt at a perl based alternative to Logstash and similar pieces of software.  It is meant to be vastly simpler and hopefully more scaleable.

## Architecture

The basic architecture looks like this:

```
Client --(syslog)--> RSyslog Server --(JSON)--> Beanstalk Job Queue --(JSON)--> Logchunk --(tokenised data)--> somewhere e.g. elasticsearch.
```

## Setup

You will need a working beanstalkd server running.  It is very simple to install and generally available via your systems package manager and requires little more that install and start to get going.  E.g:

```
apt-get install beanstalkd
service beanstalkd start
```

## Rsyslog Configuration

The Rsyslog configuration involves loading the omprog module to send the logs to a program using a template that outputs the log entry as JSON.  Config like this:

```
# Load the omprog module
Module (load="omprog")

# This template reformats the log entry into JSON.
template(name="jsonString" type="list") {
constant(value="{")
property(outname="timestamp" name="timestamp" dateFormat="rfc3339" format="jsonf")
constant(value=",")
property(outname="source_host" name="source" format="jsonf")
constant(value=",")
property(outname="severity" name="syslogseverity-text" format="jsonf")
constant(value=",")
property(outname="facility" name="syslogfacility-text" format="jsonf")
constant(value=",")
property(outname="program" name="app-name" format="jsonf")
constant(value=",")
property(outname="processid" name="procid" format="jsonf")
constant(value=",")
property(outname="message" name="msg" format="jsonf")
constant(value="}")
constant(value="\n")
}

# Send everything to the streamtobean program
*.* action(type="omprog"
           binary="/usr/local/bin/streamtobean"
           template="jsonString")

```

Copy the streamtobean/bin/streamtobean binary to /usr/local/bin and copy the streamtobean/lib/libbeanstalk.so file to /usr/local/lib.  Note that the compiled binaries suit x86_64 LInux machines.  You may have to recompile if that doesn't match your environment.

The streamtobean program accepts up to 2 arguments:
```
./streamtobean <server> <tube>
```

Server is the IP or hostname of the machine running the beanstalkd service, defaults to localhost, tube is the name of the job queue to put jobs on (beanstalk refers to queues as 'tubes'), defaults to 'syslog'.  Adjust the 'binary' option in the action of the rsyslog config as appropriate.

## Logchunk

Logchunk is a perl program that reads the jobs from beanstalk that were put there by Rsyslog, and processes them against a list of "chunkers".

An example config file for logchunk looks like:
```
# Yaml data.
---
  beanstalk_server: localhost
  beanstalk_tube: syslog

  chunkers:
    test1:
      regex: '^TEST1\sVAL1=(?<val1>[^\s]+)\sVAL2=(?<val2>[^\s]+)'
    test2:
      regex: '^TEST\sVAL1=(?<val1>[^\s]+)\sVAL2=(?<val2>[^\s]+)'
      programs: chris
      severities: notice
      facilities: user
      hosts: hicks

```

A chunker consists of a regex containing named capture groups, and optionally filters that match things like the program that generated the log, the facility the log was generated to and the severity level.  The idea being that these filters will reduce the number of logs that ultimately get compared to the regex (being a relatively expensive operation).

If a log entry matches a chunker, the regex will produce a hash from the named capture groups that will be merged onto the original hash.

The processing of a log entry will cease once a chunker successfully matches the entry.  Therefore, all the chunkers and their regexes should be very specific as to not match entries it is not intended to.

When chunkers match, a match count is incremented.  Every 100 log entries, the chunkers are reordered to put the most hit ones up front.

Note that each of programs, severities, facilities and hosts can be an array.

The program is started like this:
```
perl logchunk.pl -c /location/of/config.yaml -w <number of workers>
```

## Scaleability

The scaleability of a single worker will largely depend on the quality of the chunker regexes.  However, as it feeds off a job queue, it should scale linearly with more worker threads until there is no CPU left and then with more machines.

## Output

At this stage the output is paths are not implemented.  Im actually thinking of just having it put the results back onto a different beanstalk queue to be picked up by another process to do something with. For example, a process who's sole function is to read JSON off beanstalk and push it to Elastic Search or something similar.
