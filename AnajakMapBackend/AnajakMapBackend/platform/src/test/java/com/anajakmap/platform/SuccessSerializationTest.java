package com.anajakmap.platform;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
class SuccessSerializationTest {
 @RestController static class Sample {
  @GetMapping("/api/v1/access") Map<String,String> access(){return Map.of("allowed","true");}
  @GetMapping("/api/v1/logout") Map<String,Boolean> logout(){return Map.of("loggedOut",true);}
 }
 @Test void wrapsTypedMapsWithoutGenericSerializerErrors()throws Exception{
  var mvc=MockMvcBuilders.standaloneSetup(new Sample()).setControllerAdvice(new Success()).build();
  mvc.perform(get("/api/v1/access")).andExpect(status().isOk()).andExpect(jsonPath("$.data.allowed").value("true"));
  mvc.perform(get("/api/v1/logout")).andExpect(status().isOk()).andExpect(jsonPath("$.data.loggedOut").value(true));
 }
}
