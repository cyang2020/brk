#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

static int marker(const char *path) {
    int fd = open(path, O_WRONLY | O_TRUNC | O_CREAT, 0600);
    if (fd < 0) return errno;
    int result = write(fd, "probe\n", 6) == 6 ? 0 : errno;
    close(fd);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    printf("allowed_write_errno=%d\n", marker(argv[1]));
    printf("outside_write_errno=%d\n", marker(argv[2]));
    const char *names[] = {"com.apple.cfprefsd.agent", "com.apple.cfprefsd.daemon",
        "com.apple.securityd", "com.apple.SecurityServer", "com.apple.lsd.mapdb",
        "com.apple.cloudd", "com.apple.windowserver.active"};
    for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        mach_port_t port = MACH_PORT_NULL;
        kern_return_t result = bootstrap_look_up(bootstrap_port, names[i], &port);
        printf("mach_lookup %s result=%d\n", names[i], result);
        if (port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), port);
    }
    errno = 0;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    printf("inet_socket_result=%d errno=%d\n", fd, errno);
    if (fd >= 0) close(fd);
    return 0;
}
