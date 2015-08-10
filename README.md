# LogChunk

## CURRENT STATUS

Still very much a development piece and proof of concept.

TODO:
   * Some form of logging.
   * Define and manage failure situations appropriately.

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

Logchunk is a perl program that reads the jobs from beanstalk that were put there by Rsyslog, and processes them against a list of "chunkers" and sending the result to the appropriate output.

### Config

An example config file for logchunk looks like:
```
# Yaml data.
---
  beanstalk_server: localhost
  beanstalk_tube: syslog

  outputs:
    file:
      file: /path/to/file.log
      sort: 0 #default: 0
    elasticsearch:
      servers:
        - server1
        - server2
      index_prefix: syslog  #default: syslog
      index_rotation: daily #default: daily
      type: syslog          #default: syslog
      bulk_batch_size: 100  #default: 1
      es_options:           #default: {}
        # Other options to send to the elasticsearch constructor.
        # See https://metacpan.org/pod/Search::Elasticsearch.
        cxn_pool: 'Sniff'

  default_output: elasticsearch

  chunkers:
    test1:
      regex: '^TEST1\sVAL1=(?<val1>[^\s]+)\sVAL2=(?<val2>[^\s]+)'
      outputs:
        file:
          file: /override/default.log
    test2:
      regex: '^TEST\sVAL1=(?<val1>[^\s]+)\sVAL2=(?<val2>[^\s]+)'
      programs: chris
      severities: notice
      facilities: user
      hosts: hicks

```

### Beanstalk

The configuration options `beanstalk_server` and `beanstalk_tube` define the server address of the host running the beanstalk instance and the tube to read jobs from repectively.  Both are required.

### Outputs

Outputs define the things that can be done with a piece of log data once it has been processed.  The overall configuration of outputs is a hash where the top level keys are the name of an output type (currently 'file' or 'elasticsearch').  The value for each is also a hash of options appropriate for the output type.

A default output is nominated with the `default_output` option.  It will be used when a chunker does not explicitly define a chunker and when no chunker matches the log.

Chunkers in addition to being configured to use a chunker different to the default, can be configured to use the default but override some/all of the default options.  E.g. the default configuration for the elasticsearch output, may only define the servers and depend on the defaults for all other options.  A chunker may have configuration that inherits the servers, but then sets a different index_prefix or type.

There are currently 2 available outputs:

#### File

The most simple output is to just write the result to a file.  The file output has 2 options that can be configured:

   * `file` (String) : The absolute path to the file to write the results to.  Logchunk will attempt to create the path and file if they do not exist.
   * `sort` (Boolean): The result of a processed log will be a hash.  Typically, hashes are not sorted and when they are converted to JSON, they are not sorted either.  This does make the file hard to read for a human.  If you want to be able read it, you may like to set this to `1` (true).  This will result in the keys in the JSON strings being sorted and written to disk consistantly.  *There is a performance impact here. Don't turn it on unless you need it*.

#### Elasticsearch

Elasticsearch is like a nosql database with some search optimised indexing and query tools.  Once your log data is "chunked" into structured data, Elasticsearch is a good place for it to go.  There are a number of options to configure here, most of them have a reasonable default however:

   * `servers` (String or Array of Strings)      : The hostname or IP address and port of machine(s) running elasticsearch. E.g. es.example.com:9200.
   * `index_prefix` (String)  : Default: `syslog`: A string to form the name of the indexes used.
   * `index_rotation` (String): Default: `daily` : How often to roll to a new index. Valid options are `daily`, `weekly`, 'monthly`, 'yearly`. A date like string is appended to `index_prefix` to derive the index name.
   * `type` (String)          : Default: `syslog`: The name of the type of document.
   * `bulk_batch_size` (Int)  : Default: `1`     : The number of documents to store before doing a bulk load to Elasticsearch.  A higher number arguably offers better performance at the risk of loosing logs if the process crashes/stops.
   * `es_options` (Hash)      : Default: `{}`    : Additional options to send to the Search::Elasticsearch constructor.

### Chunkers

A chunker consists of a regex containing named capture groups, and optionally filters that match things like the program that generated the log, the facility the log was generated to and the severity level.  The idea being that these filters will reduce the number of logs that ultimately get compared to the regex (being a relatively expensive operation).

If a log entry matches a chunker, the regex will produce a hash from the named capture groups that will be merged onto the original hash.

The processing of a log entry will cease once a chunker successfully matches the entry.  Therefore, all the chunkers and their regexes should be very specific as to not match entries it is not intended to.

When chunkers match, a match count is incremented.  Every 100 log entries, the chunkers are reordered to put the most hit ones up front.

Note that each of programs, severities, facilities and hosts can be an array.

The following options are available on a chunker:

   * `regex`      (String)            : Required. The regex should contain named capures (e.g. /(*?<val1>*foo)/) the names will become keys in the resulting hash.
   * `hosts`      ((Array of) Strings): Optional. Only match logs from the hosts listed.
   * `facilities` ((Array of) Strings): Optional. Only match logs from the listed facilities. E.g. `local0`, `cron`, `kern` etc.
   * `programs`   ((Array of) Strings): Optional. Only match logs from the listed programs.
   * `severities` ((Array of) Strings): Optional. Only match logs from the listed severities.

### Usage

The program is started like this:
```
perl logchunk.pl -c /location/of/config.yaml -w <number of workers>
```

## Scaleability

The scaleability of a single worker will largely depend on the quality of the chunker regexes.  However, as it feeds off a job queue, it should scale linearly with more worker threads until there is no CPU left and then with more machines.
