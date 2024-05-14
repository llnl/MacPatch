import argparse
from mpconsole import create_app

if __name__ == '__main__':

	parser = argparse.ArgumentParser()
	parser.add_argument('--run',      default=False, action='store_true', dest='isRun', help='Run the app')
	parser.add_argument('--version',  default=False, action='store_true', dest='isVersion', help='API Version')
	parser.add_argument('--debug',    default=False, action='store_true', dest='isDebug', help='Run the app with Flask Debug On')
	parser.add_argument('--local',    default=False, action='store_true', dest='isLocal', help='Run the app with Flask Debug On')
	args = parser.parse_args()

	app = create_app()
	
	if args.isRun:
		if args.isLocal:
			app.run(host='127.0.0.1', port=8001)
		else:
			app.run(host='0.0.0.0', port=8001)

	if args.isVersion:
		print("MPConsole v3.8.0")