import heketi
import argparse
import sys

def backup(host, user, key, output_file=None):
    client = heketi.HeketiClient(host, user, key)
    req = client._make_request('GET', '/backup/db')

    if output_file is None:
        output = sys.stdout
    else:
        try:
            output = open(output_file, "w")
        except IOError as e:
            print "IOError: Could not open file for writing: {0}".format(e.strerror)
            sys.exit(1)
        except:
            print "Unexpected error:", sys.exc_info()[0]
            sys.exit(1)

    try:
        output.write(req.content)
    except IOError as e:
        print "IOError: Could not write to output: {0}".format(e.strerror)
        sys.exit(1)
    except:
        print "Unexpected error:", sys.exc_info()[0]
        sys.exit(1)
    finally:
        if output_file is not None:
            output.close()

def main():
    parser = argparse.ArgumentParser(description="Backup Heketi's BoltDB database")
    parser.add_argument('--host',
                        help='The Heketi API endpoint',
                        dest='host',
                        required=True)
    parser.add_argument('--user',
                        help='The Heketi user',
                        dest='user',
                        required=True)
    parser.add_argument('--key',
                        help='The secret key for the Heketi user',
                        dest='key',
                        required=True)
    parser.add_argument('--file',
                        help='The output file for the backup. Output to stdout if not specified.',
                        dest='output_file',
                        default=None)

    args = parser.parse_args()

    backup(args.host, args.user, args.key, args.output_file)

if __name__ == "__main__":
    main()
