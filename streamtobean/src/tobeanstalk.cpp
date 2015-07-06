//============================================================================
// Name        : rbeanstalk.cpp
// Author      : Chris Portman
// Version     : 0.0.1
// Description : Read in strings via STDIN and add them to beanstalk.
//============================================================================

#include <iostream>
#include <beanstalkpp.h>

using namespace std;
using namespace Beanstalkpp;

void usage(string progname) {
	cout << progname << " <server> <tube>" << endl;
}

int main(int argc, const char **argv) {
	string progname = argv[0];
	string server;
	string tube;
	int port = 11300;

	if (argc > 3) {
		usage(progname);
		return 1;
	} else if (argc == 3) {
		server = argv[1];
		tube = argv[2];
	} else if (argc == 2) {
		server = argv[1];
		tube = "syslog";
	} else {
		if (strcmp(argv[1], "help") == 0) {
			usage(progname);
			return 1;
		}
		server = "localhost";
		tube = "syslog";
	}

	Client bsClient(server, port);

	try {
		bsClient.connect();
		bsClient.use(tube);
	} catch (ServerException& e) {
		cout << "Could not init beanstalk connection to " << server << ": "
				<< e.getReason() << " - " << e.what() << endl;
		return 2;
	} catch (Exception& e) {
		cout << "Could not init beanstalk connection to " << server << ": "
				<< e.what() << endl;
		return 2;
	}

	string input;
	while (true) {
		getline(cin, input);

		if (cin.eof() || input.empty()) {
			break;
		}

		try {
			bsClient.put(input);
		} catch (ServerException& e) {
			cout << "Could not put job on beanstalk: " << e.getReason() << " - "
					<< e.what() << endl;
			return 2;
		}
	}

	return 0;
}
