


Connection:

1. The host starts a Julia process for the worker
2. The worker finds a free port and starts a TCP server
3. The worker writes the chosen port to stdout
4. The host reads the port number from stdout
5. The host connects to the worker's server, we now have an open TCP socket

Communication (either direction):

1. Send `msg_type::UInt8`
2. Send `message_id::UInt64`
3. Send your message data
4. (Not yet implemented) send the message boundary



Message data:

from_host_call_with_response

(f, args, kwargs, respond_with_nothing::Bool)

from_host_call_without_response

(f, args, kwargs, this_value_is_ignored::Bool)


from_host_fake_interrupt
# (this is not yet implemented)
()




from_worker_call_result

result

from_worker_call_failure

result






