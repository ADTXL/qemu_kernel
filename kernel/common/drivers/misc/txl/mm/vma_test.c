#include <linux/module.h>
#include <linux/init.h>
#include <linux/mm.h>
#include <linux/sched.h>

/*
 *遍历一个用户进程中所有的VMA，并且打印这些VMA的属性信息，比如VMA的大小，起始地址
 * */

static int pid;
module_param(pid, int, S_IRUGO);

static void printit(struct task_struct *tsk)
{
    struct mm_struct *mm;
    struct vm_area_struct *vma;
    int j = 0;
    unsigned long start, end, length;

    mm = tsk->mm;
    pr_info("mm = %p\n", mm);
    vma = mm->mmap;
    /* 使用mmap_sem读写信号量进行保护  */
    down_read(&mm->mmap_sem);
    pr_info(
        "vmas:            vma    start    end     length\n");
    while(vma) {
        j++;
        start = vma->vm_start;
        end = vma->vm_end;
        length = end - start;
        pr_info("%6d: %16p %12lx %12lx  %8lx=%8ld\n", j, vma, start, end, length, length);
        vma = vma->vm_next;
    }
    up_read(&mm->mmap_sem);
}

static int __init my_init(void)
{
    struct task_struct *tsk;
    if (pid == 0) {
        tsk = current;
        pid = current->pid;
    } else {
        tsk = pid_task(find_vpid(pid), PIDTYPE_PID);
    }
    if (!tsk)
        return -1;
    pr_info(" Examining vma's for pid=%d, command=%s \n", pid, tsk->comm);
    printit(tsk);
    return 0;
}

static void __exit my_exit(void)
{
    pr_info("Module Unloading\n");
}


module_init(my_init);
module_exit(my_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Ben ShuShu");

