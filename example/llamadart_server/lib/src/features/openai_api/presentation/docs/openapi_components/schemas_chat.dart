import 'chat_schemas/primitives.dart';
import 'chat_schemas/request.dart';
import 'chat_schemas/response.dart';

Map<String, dynamic> buildChatSchemas({required String modelId}) {
  return <String, dynamic>{
    ...buildChatPrimitiveSchemas(),
    ...buildChatRequestSchemas(modelId: modelId),
    ...buildChatResponseSchemas(modelId: modelId),
  };
}
