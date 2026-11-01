import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectSocket(Uri uri, String token) =>
    WebSocketChannel.connect(
      uri.replace(
        queryParameters: {...uri.queryParameters, 'access_token': token},
      ),
    );
