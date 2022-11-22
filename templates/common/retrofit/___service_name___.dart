import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
// this is necessary for the generated code to find your class
part '___service_name___.g.dart';

@RestApi()
abstract class ___ServiceName___Service {
  // helper methods that help you instantiate your service
  factory ___ServiceName___Service(Dio dio, {String baseUrl}) =
      ____ServiceName___Service;

  @GET('/api/___service-name___')
  Future<void> list({
    @Queries() required Object query,
  });

  // @POST('/api/___service-name___')
  // Future<void> update({
  //   @Body() required Object body,
  // });
}
