from builtin.error import Error
from MojoBridge.DTypes import (
    cudaError_t,
    cudaSuccess,
    cudaErrorName,
    cudaErrorMessage,
)

fn abortOnCudaError(
    file: String,
    line: Int,
    cmd: String,
    error: String,
    message: String,
    description: String = ""
) raises:
    var out = String("\n")
    out += file + ", line " + String(line) + ":\n"
    out += "cudaCheck(" + cmd + ");\n"
    out += error + ": " + message + "\n"
    if description != "":
        out += description + "\n"

    # In Mojo, the runtime can print a stack trace when the Error is raised,
    # if MOJO_ENABLE_STACK_TRACE_ON_ERROR is set. 
    # MOJO_ENABLE_STACK_TRACE_ON_ERROR=1 mojo build --debug-level full your_program.mojo
    #./your_program
    out += "\n"

    raise Error(out)


@always_inline("nodebug")
fn cudaCheck_(
    file: String,
    line: Int,
    cmd: String,
    result: cudaError_t,
    description: String = ""
) raises -> Bool:
    if result == cudaSuccess:
        return True
    var error = cudaErrorName(result)
    var message = cudaErrorMessage(result)
    abortOnCudaError(file, line, cmd, error, message, description)
    return False
