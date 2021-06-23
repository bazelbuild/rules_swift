#include <nlohmann/json.hpp>

class WorkRequest {
 public:
  WorkRequest(int32_t request_id, const std::vector<std::string> &args)
      : request_id_(request_id), arguments_(args){};

  const std::vector<std::string> arguments() const { return arguments_; };

  const int32_t request_id() const { return request_id_; }

 private:
  int32_t request_id_;
  std::vector<std::string> arguments_;
};

class WorkResponse {
 public:
  WorkResponse(){};

  nlohmann::json to_json() {
    return nlohmann::json{
        {"exitCode", this->exit_code_},
        {"output", this->output_},
        {"requestId", this->request_id_},
    };
  }

  void set_exit_code(int exit_code) { exit_code_ = exit_code; }

  void set_output(std::string output) { output_ = output; }

  void set_request_id(int32_t request_id) { request_id_ = request_id; }

 private:
  int exit_code_;
  std::string output_;
  int32_t request_id_;
};
