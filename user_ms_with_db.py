from flask import Flask, request, jsonify
import sqlite3
import base64
from flask_cors import CORS

count_http_request = 0

app = Flask(__name__)


def is_sha1(maybe_sha):
    if len(maybe_sha) != 40:
        return False
    try:
        sha_int = int(maybe_sha, 16)
    except ValueError:
        return False
    return True


def isBase64(sb):
    try:
        if type(sb) == str:
            sb_bytes = bytes(sb, 'ascii')
        elif type(sb) == bytes:
            sb_bytes = sb
        else:
            raise ValueError("Argument must be string or bytes")
        return base64.b64encode(base64.b64decode(sb_bytes)) == sb_bytes
    except Exception:
        return False


def add_count():
    global count_http_request
    count_http_request += 1


app = Flask(__name__)
api = CORS(app)


@app.errorhandler(405)
def func(e):
    add_count()
    return "", 405


@app.route('/api/v1/_count', methods=['GET'])
def http_count():
    if (request.method == 'GET'):
        return jsonify(list([count_http_request])), 200
    else:
        return jsonify({"message": "Method not allowed"}), 405


@app.route('/api/v1/_count', methods=['DELETE'])
def http_count_reset():
    global count_http_request
    if (request.method == 'DELETE'):
        count_http_request = 0
        return jsonify({}), 200
    else:
        return jsonify({"message": "Method not allowed"}), 405

# 1 Add user--------------------------------------------------------------------


@app.route('/api/v1/users', methods=['POST'])
def add_user():
    add_count()
    if (request.method == 'POST'):
        with sqlite3.connect("users.db") as connectionState:
            cursor = connectionState.cursor()

            if not request.json or not 'username' in request.json or not 'password' in request.json:
                return jsonify({"message": "username or password missing"}), 400

            username = request.json['username']
            password = request.json['password']

            users = cursor.execute("select Username from User")
            users = list(users)
            users = [users[i][0] for i in range(0, len(users))]

            if username in users:
                return jsonify({"message": "user {} already exists".format(username)}), 400

            if not is_sha1(request.json['password']):
                return jsonify({"message": "password not in sha1 format. Enter a proper format"}), 400

            cursor.execute("insert into User values (?, ?)",
                           (username, password))
            return jsonify({"message": "User {} added".format(request.json['username'])}), 201
    else:
        return jsonify({"message": "Method not allowed"}), 405

# 2 Remove user-----------------------------------------------------------------


@app.route('/api/v1/users/<username>', methods=['DELETE'])
def remove_user(username):
    add_count()
    if (request.method == 'DELETE'):
        with sqlite3.connect("users.db") as connectionState:
            cursor = connectionState.cursor()
            users = cursor.execute("select Username from User")
            users = list(users)
            print(username)
            print(users)
            users = [users[i][0] for i in range(0, len(users))]
            if username in users:
                cursor.execute(
                    "delete from User where Username=(?)", (username,))
                return jsonify({"message": "user {} removed".format(username)}), 200
            else:
                return jsonify({"message": "User doesn't exist"}), 400
    else:
        return jsonify({"message": "Method not allowed"}), 405

# 3 List all users--------------------------------------------------------------


@app.route('/api/v1/users', methods=['GET'])
def list_all_users():
    add_count()
    if (request.method == 'GET'):
        with sqlite3.connect("users.db") as connectionState:
            cursor = connectionState.cursor()
            users = cursor.execute("select Username from User")
            users = list(users)
            print(users)
            users = [users[i][0] for i in range(0, len(users))]
            if (users == []):
                return jsonify({"message": "No users"}), 204
            else:
                return jsonify(users), 200
    else:
        return jsonify({"message": "Method not allowed"}), 405


@app.route('/')
def home():
    return "User management microservice is working!\nOwner: CloudComp2"


if __name__ == '__main__':
    # app.run(debug=True,port=8000)
    app.run(host="0.0.0.0", port=80)
