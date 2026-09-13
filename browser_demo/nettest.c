#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>

int main(void) {
  printf("nettest: starting\n");
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = PF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  struct addrinfo * res = NULL;
  int gai = getaddrinfo("127.0.0.1", "10000", &hints, &res);
  printf("nettest: getaddrinfo rc=%d errno=%d (%s)\n", gai, errno, strerror(errno));
  if (gai != 0 || res == NULL) {
    printf("nettest: getaddrinfo failed, aborting\n");
    return 1;
  }
  int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  printf("nettest: socket() fd=%d errno=%d (%s)\n", fd, errno, strerror(errno));
  if (fd < 0) {
    return 1;
  }
  int rc = connect(fd, res->ai_addr, res->ai_addrlen);
  printf("nettest: connect() rc=%d errno=%d (%s)\n", rc, errno, strerror(errno));
  printf("nettest: done\n");
  return 0;
}
