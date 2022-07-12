/*
 *实验目的：
 （1）写一个内核模块，在/proc中创建一个名为“test”的目录
 （2）在test目录下面分别创建两个节点，分别是read和write。从read节点中可以
 读取内核模块的某个全局变量的值，往write节点写数据可以修改某个全局变量的值
 *
 * */


#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/init.h>

#define NODE_READ "read"
#define NODE_WRITE "write"

static int param = 100;
static struct proc_dir_entry *my_root;
static struct proc_dir_entry *my_read_proc;
static struct proc_dir_entry *my_write_proc;

#define KS 32
static char kstring[KS];    // should be less sloppy about overflows



static ssize_t my_read(struct file *file, char __user *buf, size_t lbuf, loff_t *ppos)
{
    int nbytes = sprintf(kstring, "%d\n", param);
    //pr_info("the value of nbytes is  %d\n", nbytes);
    //pr_info("the kstriing is   %s\n", kstring);
    return simple_read_from_buffer(buf, lbuf, ppos, kstring, nbytes);
}

static ssize_t my_write(struct file *file, const char __user *buf, size_t lbuf, loff_t *ppos)
{
    ssize_t rc;
    rc = simple_write_to_buffer(kstring, lbuf, ppos, buf, lbuf);
    sscanf(kstring, "%d", &param);
    pr_info("param has been set to %d\n", param);
    return rc;
}

static const struct file_operations read_proc_fops = {
    .owner = THIS_MODULE,
    .read = my_read,
};

static const struct file_operations write_proc_fops = {
    .owner = THIS_MODULE,
    .write = my_write,
};

static int __init my_init(void)
{
    my_root = proc_mkdir("test", NULL);
    if (IS_ERR(my_root)) {
        pr_err("failed to make test dir\n");
        return -1;
    }

    my_read_proc = proc_create(NODE_READ, 0444, my_root, &read_proc_fops);
    if (IS_ERR(my_read_proc)) {
        pr_err("failed to make %s node\n", NODE_READ);
        return -1;
    }

    my_write_proc = proc_create(NODE_WRITE, 0222, my_root, &write_proc_fops);
    if (IS_ERR(my_read_proc)) {
        pr_err("failed to make %s node\n", NODE_WRITE);
        return -1;
    }

    pr_info("created %s and %s node\n", NODE_READ, NODE_WRITE);

    return 0;
}

static void __exit my_exit(void)
{
    if (my_read_proc) {
        proc_remove(my_read_proc);
        proc_remove(my_write_proc);
        proc_remove(my_root);
        pr_info("Removed %s and %s. \n", NODE_READ, NODE_WRITE);
    }
}



module_init(my_init);
module_exit(my_exit);
MODULE_LICENSE("GPL");

