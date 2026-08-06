# Container & Kubernetes Runtime Security – Bảo vệ workload khi đang chạy

Supply-chain control giúp biết artifact nào được phép triển khai. Runtime security trả lời phần còn lại:

> Khi artifact bắt đầu chạy, nó được cấp identity, syscall, filesystem, network, secret và quyền truy cập
> host nào; hệ thống phát hiện và cô lập ra sao nếu process đó bị compromise?

Chương này tập trung vào Kubernetes trên Linux. Windows workload có security model khác và phải dùng
baseline riêng, không sao chép nguyên các trường Linux.

---

## 1. Container là isolation bằng kernel, không phải máy ảo nhỏ

Container thường chia sẻ kernel của node. Namespace tách góc nhìn process/network/mount; cgroup giới hạn
tài nguyên; capability, seccomp và LSM hạn chế hành vi. Sai cấu hình hoặc kernel/runtime vulnerability có
thể biến compromise trong container thành compromise node.

```text
application process
  → container boundary
    → pod boundary
      → node kernel/runtime
        → cluster API + cloud/network/storage
```

Không có một “cờ bảo mật” duy nhất. Defense in depth phải giảm quyền ở từng lớp và giả định lớp trước có
thể thất bại.

## 2. Threat model từ workload đến cluster

| Entry point | Attack path | Impact có thể có |
|---|---|---|
| Lỗ hổng ứng dụng | RCE → đọc token/secret → gọi API | chiếm dữ liệu hoặc namespace |
| Image độc hại | startup hook/process lạ | exfiltration, persistence |
| Pod quá quyền | privileged/hostPath/capability | container escape, node takeover |
| Network mở | lateral movement/metadata access | cloud credential, dịch vụ nội bộ |
| ServiceAccount rộng | tạo workload/bind role/read secret | privilege escalation cluster |
| Node compromise | đọc pod data/token, điều khiển runtime | mọi workload trên node |
| Admission bypass | CRI/static pod/direct node change | chạy workload ngoài policy |

Threat statement nên gắn workload, namespace, node pool, identity, data và blast radius cụ thể.

## 3. Runtime security là chuỗi control

```text
verified image digest
  → authenticate + authorize API request
  → mutate/validate admission
  → schedule vào node phù hợp
  → kubelet/CRI tạo sandbox
  → kernel controls + network/storage policy
  → runtime telemetry
  → contain + revoke + replace
```

Admission ngăn cấu hình xấu trước khi chạy; kernel control giới hạn process sau khi chạy; runtime detection
phát hiện hành vi không dự kiến. Thiếu một mắt xích sẽ làm control khác gánh trách nhiệm mà nó không có.

## 4. Inventory workload và mức tin cậy

Mỗi workload cần metadata tối thiểu:

- owner, service, environment, criticality và dữ liệu xử lý;
- image digest, provenance và thời điểm deploy;
- ServiceAccount/RBAC, cloud identity và secret được mount;
- ingress/egress cần thiết;
- volume, device, host namespace và runtime class;
- node pool/tenant, policy exception và expiry;
- expected process, child process, file write và outbound destination.

Runtime detection khó chính xác nếu không biết “bình thường” là gì. Inventory phải phản ánh digest đang
chạy, không chỉ tag hoặc manifest mong muốn trong Git.

## 5. Namespace là scope quản trị, không phải hard isolation

Namespace giúp scope name, RBAC, quota, NetworkPolicy và Pod Security Admission. Nó không tạo kernel,
node hay control plane riêng. Workload ở hai namespace vẫn có thể cùng node và dùng chung cluster API.

Phân vùng namespace theo tenant/team/environment; dùng label do platform quản lý để gắn policy. Không cho
tenant tự sửa label có ý nghĩa security.

Với tenant đối nghịch, yêu cầu compliance mạnh hoặc blast radius không chấp nhận được, dùng cluster/node
pool riêng hoặc sandbox runtime mạnh hơn thay vì chỉ dựa vào namespace.

## 6. Mọi container trong Pod chia sẻ trust boundary đáng kể

Init container, app container, sidecar và ephemeral container có thể chia sẻ network namespace, volume và
ServiceAccount token tùy cấu hình. Sidecar compromise có thể quan sát localhost traffic hoặc file chung.

Nguyên tắc:

- chỉ ghép container khi chúng thực sự cùng trust level;
- không để sidecar ít tin cậy đọc volume/secret của app;
- review init container vì nó có thể sửa file trước khi app chạy;
- kiểm soát RBAC cho subresource `pods/ephemeralcontainers`;
- audit `exec`, `attach`, `portforward` và debug container.

“Chỉ là sidecar quan sát” không đồng nghĩa ít quyền.

## 7. Đường đi của một API request

Request tạo workload thường đi qua:

```text
TLS → authentication → authorization → mutating admission
    → schema/defaulting → validating admission → persistence
```

Admission chỉ đánh giá object đi qua API server. Static Pod, người có quyền trên node, CRI socket hoặc
kubelet bị compromise có thể tạo/thay process ngoài con đường này. Vì vậy cần đồng thời bảo vệ node,
runtime socket và phát hiện desired state khác observed state.

## 8. RBAC là điều kiện trước của runtime security

Quyền tạo/patch Pod hoặc workload controller gần như là quyền thực thi code trong namespace. Các quyền
`create pods`, `pods/exec`, `pods/ephemeralcontainers`, `bind`, `escalate`, `impersonate`, đọc Secret và sửa
admission policy đều nhạy cảm.

Không cấp wildcard nếu không cần; tách deployer, debugger và policy admin. Kiểm tra privilege escalation
gián tiếp: người không đọc Secret nhưng tạo Pod có thể mount Secret; người tạo Pod trên node đặc quyền có
thể tiếp cận host.

Chi tiết mô hình RBAC nằm trong
[Kubernetes RBAC & Policy Deep Dive](../../kubernetes/security/rbac_deep.md).

## 9. ServiceAccount riêng cho từng workload

Không dùng `default` ServiceAccount cho cả namespace. Tạo identity theo workload/purpose, chỉ bind verb và
resource cần thiết, tránh ClusterRole nếu namespace Role đủ.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-api
  namespace: production
automountServiceAccountToken: false
```

Đặt `automountServiceAccountToken: false` khi workload không gọi Kubernetes API. Bật token projection chỉ
ở container/path thực sự cần. ServiceAccount identity không tự cấp quyền; RoleBinding/ClusterRoleBinding
và external workload identity mới quyết định khả năng thực tế.

## 10. Projected token ngắn hạn và audience

Token ServiceAccount hiện đại nên là bound, time-limited projected token thay vì legacy Secret token lâu dài.

```yaml
volumes:
  - name: api-token
    projected:
      sources:
        - serviceAccountToken:
            path: token
            audience: orders.internal
            expirationSeconds: 3600
```

Consumer phải kiểm tra issuer, signature, audience, expiry và subject. Audience khác nhau cho Kubernetes API
và dịch vụ nội bộ để tránh token dùng sai mục đích. Token ngắn hạn vẫn cần revoke/contain nhanh vì attacker
có thể dùng nó trong cửa sổ còn hiệu lực.

## 11. Pod Security Standards: ba mức chính

Kubernetes định nghĩa ba profile:

| Profile | Mục đích |
|---|---|
| Privileged | không hạn chế; dành cho system workload đặc biệt |
| Baseline | chặn privilege escalation phổ biến, ít ảnh hưởng ứng dụng |
| Restricted | hardening mạnh theo best practice hiện hành |

Restricted là đích phù hợp cho phần lớn application workload. System DaemonSet như CNI/CSI/security agent
có thể cần exception nhưng phải chạy trong namespace/node pool được quản trị, có owner và scope nhỏ.

PSS không kiểm tra mọi requirement như image provenance, registry, label ownership hay NetworkPolicy.

## 12. Pod Security Admission và rollout an toàn

Pod Security Admission áp profile bằng namespace label với ba mode:

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Rollout nên đi `audit/warn → sửa workload → enforce`, theo dõi violation và controller template. Có thể pin
version để tránh policy đổi bất ngờ khi cluster nâng cấp; lập kế hoạch cập nhật version sau khi test.

Namespace exempt là bypass lớn: inventory, giới hạn actor, alert thay đổi và review định kỳ.

## 13. Admission policy: built-in, CEL và webhook

Các lớp bổ sung nhau:

- Pod Security Admission cho baseline/restricted chuẩn;
- ValidatingAdmissionPolicy dùng CEL trong API server, phù hợp rule validation không cần external call;
- Gatekeeper/Kyverno hoặc webhook cho policy phức tạp, mutation/report/ecosystem riêng;
- image verifier kiểm tra digest, signature, provenance và attestation.

Policy nên đánh giá object cuối cùng sau mutation và có test fixture. Tránh nhiều engine cùng mutate một
field khiến kết quả phụ thuộc thứ tự hoặc khó giải thích.

## 14. Admission webhook cũng là critical infrastructure

Webhook có thể làm cluster mất khả năng deploy hoặc tạo lỗ hổng fail-open. Cần:

- scope bằng namespace/object selector, không nhận mọi request nếu không cần;
- timeout ngắn, replica đa node/zone và resource request/limit;
- TLS trust, network policy và ServiceAccount tối thiểu;
- `sideEffects`, match policy và API version khai báo đúng;
- chọn `failurePolicy` theo rủi ro và availability;
- monitor latency, error, timeout, rejection và bypass;
- break-glass có approval, expiry, audit và hậu kiểm.

Fail-closed bảo vệ security nhưng có thể chặn khôi phục cluster; thiết kế recovery path trước khi sự cố.

## 15. SecurityContext tham chiếu cho ứng dụng

```yaml
spec:
  serviceAccountName: order-api
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: registry.example.com/order-api@sha256:...
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      resources:
        requests: {cpu: 100m, memory: 128Mi}
        limits: {cpu: 500m, memory: 512Mi}
```

Đây là baseline, không phải manifest hoàn chỉnh. UID/GID, writable volume, NetworkPolicy, probes, secret và
resource phải điều chỉnh theo ứng dụng rồi kiểm thử.

## 16. Chạy non-root và định danh UID/GID

`runAsNonRoot: true` yêu cầu runtime không chạy container với UID 0, nhưng image có username không ánh xạ
rõ UID có thể gây lỗi xác minh. Image production nên khai báo numeric UID không phải 0 và không cần sửa
system path lúc startup.

`runAsUser`, `runAsGroup`, `fsGroup` ảnh hưởng file permission; không chọn UID tùy tiện mà bỏ qua ownership
của image/volume. Tránh world-writable để “sửa nhanh”.

Non-root giảm quyền trong container nhưng không thay seccomp, capability, LSM hoặc host mount policy.

## 17. Chặn privilege escalation

`allowPrivilegeEscalation: false` yêu cầu process không nhận thêm privilege qua `execve`, tương ứng cơ chế
`no_new_privs` trên Linux. Nó không có hiệu lực như mong muốn với privileged container hoặc quyền kernel
mạnh làm mất giới hạn.

Chặn setuid/setgid binary không cần thiết ngay từ image; drop capability; chạy non-root. Negative test nên
thử executable setuid và kiểm tra effective capability, không chỉ xem manifest field tồn tại.

## 18. Linux capabilities: drop tất cả rồi thêm tối thiểu

Root privilege được chia thành capability. Một số capability có blast radius rất lớn, đặc biệt
`CAP_SYS_ADMIN`; `NET_ADMIN`, `SYS_PTRACE`, `BPF`, `PERFMON`, `SYS_MODULE` cũng cần review nghiêm ngặt.

```yaml
securityContext:
  capabilities:
    drop: ["ALL"]
    add: ["NET_BIND_SERVICE"] # chỉ khi thật sự cần
```

Nếu app chỉ cần port thấp, cân nhắc dùng port không đặc quyền hoặc cấu hình nền tảng thay vì cấp capability.
Audit effective capabilities lúc chạy vì runtime/default có thể khác kỳ vọng.

## 19. Seccomp giới hạn syscall

Seccomp giảm syscall kernel mà process có thể gọi. Kubernetes hỗ trợ:

- `RuntimeDefault`: profile mặc định của container runtime;
- `Localhost`: profile do node quản lý;
- `Unconfined`: không lọc, nên bị policy chặn với workload thông thường.

Ưu tiên `RuntimeDefault` làm baseline. Custom profile cần version/distribution, rollout theo node, compatibility
test và telemetry về denial. Học syscall từ traffic bình thường có thể bỏ sót đường xử lý hiếm; dùng allowlist
quá hẹp mà không test error path sẽ gây outage.

## 20. AppArmor và SELinux là Mandatory Access Control

Seccomp kiểm soát syscall nào được gọi; AppArmor/SELinux kiểm soát process được làm gì với file, socket và
resource theo policy/label. Chúng bổ sung, không thay nhau.

Kubernetes có trường `appArmorProfile` trong SecurityContext trên node hỗ trợ AppArmor. SELinux cần label,
runtime và volume relabel tương thích. Policy phải được triển khai trên mọi node có thể schedule workload;
nếu không, Pod có thể fail hoặc chạy với protection khác dự kiến.

Không dùng `Unconfined`/disable label như cách sửa permission lâu dài.

## 21. Read-only root filesystem và vùng ghi tạm

`readOnlyRootFilesystem: true` làm persistence và sửa binary/config trong image khó hơn. Cấp vùng ghi rõ
ràng cho nhu cầu hợp lệ:

```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
  - name: tmp
    emptyDir:
      sizeLimit: 64Mi
```

Tách cache, upload và log; đặt size limit; không ghi secret vào `/tmp`. Read-only root không ngăn process
ghi volume/PVC hoặc memory, và attacker vẫn có thể chạy code trong process hiện tại.

## 22. Volume là đường nối sang dữ liệu và host

Review mỗi volume theo source, quyền đọc/ghi, data classification, lifecycle và container được mount.
`hostPath` cho workload quyền chạm filesystem node; mount `/`, `/etc`, `/proc`, runtime socket hoặc kubelet
directory có thể tương đương node takeover.

Tránh Docker/containerd/CRI socket trong application Pod. Với CSI driver hoặc node agent bắt buộc dùng
host access, cô lập namespace/node pool, pin image, giảm RBAC/capability, mount chính xác và monitor.

`readOnly: true` giảm sửa dữ liệu nhưng đọc token/config nhạy cảm vẫn là impact.

## 23. Host namespace và host port

`hostPID`, `hostIPC`, `hostNetwork` đưa workload gần host hơn:

- host PID có thể lộ process và tăng giá trị của ptrace/proc access;
- host network bỏ pod network isolation thông thường và mở port trên node;
- host IPC chia sẻ IPC object;
- hostPort làm tăng xung đột và exposure node.

PSS restricted/baseline chặn hoặc giới hạn nhiều cấu hình này. Exception phải gắn đúng DaemonSet, node pool,
capability và network need; không exempt cả namespace chứa application khác.

## 24. Privileged container và device access

Privileged container nhận quyền rất gần host, làm nhiều control như capability, seccomp hoặc LSM mất tác dụng
thực tế. Không dùng privileged chỉ để sửa một lỗi permission hoặc build image trong cluster.

Device plugin/Dynamic Resource Allocation có thể đưa GPU, accelerator hoặc device vào workload. Cần review
driver, node agent, device class, claim và actor được phép tạo claim. Một device/driver kernel lỗi có thể mở
đường sang host.

Tách node cho workload thực sự cần privileged/device và coi chúng là trust tier cao rủi ro.

## 25. Proc, sysctl và kernel tuning

Unsafe sysctl hoặc quyền ghi `/proc`/`/sys` có thể thay hành vi node/network/kernel. Chỉ allowlist namespaced
sysctl đã hiểu; cấu hình node-wide sysctl qua node management, không qua application Pod.

Giữ `procMount` mặc định, chặn mount host `/proc` và `/sys`, không cấp `SYS_ADMIN` để app tự mount. Mọi thay
đổi allowlist sysctl cần test theo kernel/runtime version và audit owner.

## 26. User namespace và rootless

User namespace ánh xạ UID 0 trong container thành UID không đặc quyền trên host, giảm impact của một số escape
path. Nó là lớp bổ sung, không làm privileged mount, kernel vulnerability hoặc quyền API biến mất.

Khi dùng Kubernetes user namespaces/rootless component, kiểm tra support của runtime, storage/volume, device,
monitoring agent và policy trên phiên bản cluster. Rollout theo node pool và test ownership backup/restore;
UID mapping sai có thể gây mất quyền truy cập dữ liệu.

## 27. RuntimeClass và sandbox runtime

`RuntimeClass` cho phép chọn runtime handler khác, ví dụ sandbox dùng userspace kernel hoặc lightweight VM.

```yaml
spec:
  runtimeClassName: sandboxed
```

gVisor tăng khoảng cách với host kernel; Kata Containers dùng VM boundary mạnh hơn nhưng có overhead và
compatibility trade-off. Dùng cho untrusted code, plugin/user job hoặc tenant rủi ro cao; gắn scheduling,
overhead và node selector đúng cấu hình.

RuntimeClass name chỉ có giá trị khi handler trên node thật sự được cấu hình và đo kiểm.

## 28. Image runtime: digest, pull và filesystem

Deploy image bằng digest đã verify. Tag có thể đổi; `imagePullPolicy: Always` vẫn không biến tag thành immutable.
Admission nên kiểm tra registry allowlist, digest, signature/provenance và trạng thái revoke.

Image tối thiểu giảm package/shell/tool attacker có thể tận dụng, nhưng distroless không sửa lỗ hổng ứng dụng.
Không cài package lúc container startup; thao tác đó phá reproducibility và cần egress/quyền ghi.

Theo dõi image thực tế từ Pod status/runtime và đối chiếu desired digest; registry credential chỉ có scope
pull cần thiết và được rotate.

## 29. Secret và configuration trong workload

Kubernetes Secret base64 không phải encryption. Bảo vệ etcd at rest, RBAC, KMS khi phù hợp và tránh cho
workload không cần thiết list/watch Secret.

Mount secret vào container/path nhỏ nhất; ưu tiên projected/CSI/dynamic credential ngắn hạn. Environment
variable dễ đi vào crash dump, debug output và child process; file cũng có rủi ro nếu permission hoặc sidecar
chung volume đọc được.

Secret compromise cần revoke tại provider, không chỉ xóa Pod/Secret object. Chi tiết xem
[Secrets & Key Management](../secrets/secrets_key_management.md).

## 30. NetworkPolicy: default deny rồi allow theo flow

NetworkPolicy chỉ có tác dụng khi network plugin hỗ trợ và thực thi. Policy là additive: traffic được phép nếu
đáp ứng union các rule áp dụng; thứ tự policy không tạo ưu tiên deny/allow kiểu firewall truyền thống.

Baseline namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-all}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Sau đó allow đúng source/destination/port. Test connectivity thực tế; object tồn tại không chứng minh dataplane
đang enforce.

## 31. Egress: DNS, metadata và control plane

Default-deny egress thường làm hỏng DNS trước. Chỉ allow DNS tới resolver được quản lý, đúng protocol/port;
sau đó allow destination cần thiết.

Đặc biệt chặn hoặc kiểm soát:

- cloud instance metadata/link-local endpoint;
- Kubernetes API nếu workload không cần;
- node/kubelet/management endpoint;
- private control plane, database và admin service;
- Internet egress tùy ý.

NetworkPolicy chuẩn không biểu diễn FQDN/L7 identity đầy đủ; dùng egress proxy/CNI extension khi cần và hiểu
DNS rebinding, NAT cùng giới hạn implementation.

## 32. L7 policy, mTLS và service mesh

NetworkPolicy L3/L4 không xác thực business identity hoặc HTTP action. Service mesh/mTLS có thể cung cấp
workload identity, encryption và L7 authorization nhưng thêm proxy/control plane/certificate lifecycle.

mTLS không thay application authorization: caller có certificate hợp lệ vẫn phải được phép thao tác resource.
Sidecar/ambient component là phần của trust boundary; compromise policy controller/CA có blast radius lớn.

Giữ network deny làm lớp cơ bản và chỉ thêm L7 khi có requirement rõ, telemetry và break-glass được test.

## 33. Resource request/limit là security control availability

Cgroup giới hạn CPU, memory và resource; request giúp scheduler tránh overcommit mù. Thiếu limit có thể cho
compromised workload gây noisy neighbor hoặc node pressure; limit quá thấp tạo restart loop và self-DoS.

Đặt request/limit theo đo đạc, alert throttling/OOM và test tải. Giới hạn ephemeral storage, `emptyDir` và log;
memory-backed `emptyDir` vẫn tiêu thụ memory của Pod/node theo cấu hình.

Resource limit không ngăn fork bomb hoàn toàn nếu thiếu PID limit và quota.

## 34. ResourceQuota, LimitRange và PID

Namespace `ResourceQuota` giới hạn tổng CPU, memory, object count, PVC và loại resource; `LimitRange` đặt
default/min/max cho container/Pod. Chúng ngăn một tenant chiếm cluster và buộc manifest có budget.

Node cần reserve resource cho system daemon và cấu hình PID limit phù hợp. Theo dõi API object explosion,
Job/CronJob không dọn, event/log storm và quota bypass qua namespace mới.

Quota là guardrail availability, không phải substitute cho authorization hay workload isolation.

## 35. Probe, hook và debug command cũng thực thi code

`exec` probe và lifecycle hook chạy command trong container; HTTP/TCP probe tạo traffic định kỳ. Không đưa
secret vào command/URL; tránh shell string phức tạp; giới hạn endpoint probe không trả dữ liệu nhạy cảm.

Liveness sai có thể gây restart storm; readiness sai có thể gửi traffic vào instance chưa an toàn; startup
probe bảo vệ app khởi động chậm. Container restart không “làm sạch” node hoặc volume khi compromise.

Audit `kubectl exec`, attach, port-forward và ephemeral debug; dùng image debug đã quản lý, không tải tool tùy ý.

## 36. Scheduling theo trust tier

Tách node pool cho:

- system/privileged daemon;
- application thông thường;
- untrusted/sandboxed job;
- regulated/high-value workload;
- GPU/device workload.

Dùng taint/toleration để ngăn schedule vô ý, affinity/node selector để chọn node phù hợp và admission để
kiểm tra tổ hợp. Toleration chỉ cho phép schedule, không chứng minh workload đáng tin; actor tự thêm toleration
phải bị policy/RBAC giới hạn.

Không dùng label mà kubelet có thể tự gắn làm trust signal nếu chưa được NodeRestriction bảo vệ.

## 37. Hardening worker node

Node chạy kernel, kubelet, CRI, CNI/CSI và mọi Pod trên nó. Baseline:

- OS/image tối thiểu, patch kernel/runtime nhanh và immutable/rebuild khi khả thi;
- SSH/admin access ít, MFA/JIT và audit;
- firewall management port, không expose kubelet/CRI;
- secure boot/measured boot/TPM khi threat model yêu cầu;
- file permission cho kubeconfig, PKI và runtime socket;
- read-only/locked node filesystem theo nền tảng;
- đồng bộ thời gian và gửi log ra ngoài node;
- cordon/drain/recreate, không sửa thủ công kéo dài.

Node health “Ready” không phải integrity attestation.

## 38. Kubelet, CRI và runtime socket

Ai điều khiển kubelet hoặc CRI/containerd socket có thể tạo process, mount filesystem và thao tác container
ngoài admission policy. Không mount socket vào workload thông thường; giới hạn node-local agent bắt buộc.

Kubelet phải dùng authentication/authorization phù hợp, tắt anonymous access và chỉ expose endpoint cần thiết.
CRI/runtime config, plugin directory và binary phải được quản lý như privileged code.

Runtime upgrade cần compatibility test nhưng không trì hoãn vô hạn security patch; có canary node pool và
khả năng drain/rollback.

## 39. Node identity, Node authorizer và NodeRestriction

Kubelet có identity riêng. Node authorizer giới hạn node chỉ đọc/sửa resource liên quan workload được gán;
NodeRestriction admission hạn chế kubelet sửa Node/Pod nhạy cảm và bảo vệ một số label prefix.

Không cấp `system:nodes` hoặc certificate node cho workload/user. Certificate bootstrap/rotation, node name
và cloud instance identity phải liên kết đúng; node giả có thể xin workload và secret nếu bootstrap trust yếu.

Label dùng để schedule workload nhạy cảm phải nằm trong namespace label được bảo vệ khỏi kubelet tự sửa.

## 40. Control plane, etcd và đường vòng API server

API server, scheduler, controller manager, cloud controller và etcd là control plane. Bảo vệ network endpoint,
PKI, admin identity, encryption at rest, backup/restore và audit. Etcd access thường tương đương đọc/sửa trạng
thái cluster, gồm Secret nếu không có protection phù hợp.

Admission không nhìn thấy thay đổi trực tiếp ở etcd, node/CRI hoặc static Pod manifest. Monitor static Pod,
runtime process và desired-vs-observed drift; hạn chế host access có thể sửa manifest control plane.

Backup etcd phải encrypted, access-controlled, tested và cùng scope retention với dữ liệu nguồn.

## 41. Kubernetes audit log là control-plane evidence

Audit policy chọn level:

- `Metadata`: ai, khi nào, resource/verb nào;
- `Request`: thêm request body;
- `RequestResponse`: thêm response body, rủi ro dữ liệu cao;
- `None`: bỏ qua event.

Ghi đủ create/patch/delete, RBAC, Secret access metadata, exec/attach/portforward, ephemeral container, admission
policy, namespace security label và node action. Redact/tránh body chứa Secret hoặc token.

Gửi log bất biến ra ngoài cluster/control plane, đồng bộ thời gian, theo dõi drop/backend failure và test truy
vấn theo user, source IP, userAgent, object UID và audit ID.

## 42. Runtime telemetry nhìn thấy hành vi trong process

API audit thấy ý định control plane; runtime telemetry thấy syscall/process/file/network trên node/container.
Công cụ như Falco hoặc eBPF sensor có thể cảnh báo:

- shell hoặc package manager trong container production;
- write vào binary/config path;
- đọc token/secret path bất thường;
- process mở runtime socket hoặc host namespace;
- outbound connection hiếm;
- capability/syscall nhạy cảm;
- crypto miner, reverse shell hoặc persistence pattern.

Sensor cần chính nó được harden; agent thường có host access cao và trở thành supply-chain/runtime target.

## 43. Detection engineering theo workload context

Rule tốt kết hợp event với Kubernetes metadata: cluster, namespace, workload UID, container, image digest,
ServiceAccount, node, process lineage và destination. Pod name ngắn hạn không đủ làm identity.

Quy trình tuning:

1. xác định behavior/invariant và attacker path;
2. chạy audit/shadow, phân loại expected exception;
3. thêm scope theo digest/workload, không exclude cả namespace;
4. đặt severity theo privilege, exposure và asset;
5. gắn runbook, owner, evidence cần thu;
6. test lại khi image/runtime/kernel thay đổi.

Không coi số alert bằng 0 là an toàn; đo coverage và khả năng phát hiện kịch bản đã giả lập.

## 44. Runbook: một workload/container bị compromise

1. Xác minh alert và ghi timestamp, cluster, namespace, Pod UID, node, image digest, ServiceAccount.
2. Bảo toàn API audit, runtime event, process/network evidence và workload spec trước khi xóa.
3. Chặn ingress/egress hoặc scale/quarantine theo mức rủi ro; tránh để controller lập tức tạo bản sao xấu.
4. Revoke cloud/API credential và secret workload có thể đọc.
5. Tìm cùng digest, token, node, destination và behavior trên toàn fleet.
6. Xác định entry point; patch source/dependency/config và tạo artifact mới đã verify.
7. Redeploy trên node tin cậy, theo dõi enhanced detection.
8. Cập nhật policy, rule và retrospective.

Xóa Pod chỉ xóa một biểu hiện; token, PVC, node hoặc image xấu vẫn có thể còn.

## 45. Runbook: node bị compromise

1. Cordon node và ngăn workload mới; cô lập network quản trị theo runbook.
2. Ghi danh sách Pod/digest/identity/volume từng chạy và thu evidence phù hợp trước drain nếu có thể.
3. Giả định secret/token của workload trên node có thể lộ; ưu tiên revoke theo blast radius.
4. Kiểm tra kubelet certificate, cloud instance role, runtime/CNI/CSI credential và node-access identity.
5. Hunt lateral movement sang API, registry, storage và node khác.
6. Thay/reimage node từ nguồn tin cậy; không “dọn malware” rồi đưa lại production.
7. Chỉ uncordon replacement sau integrity/config/policy verification.

Nếu control plane credential xuất hiện trên node, nâng severity và mở rộng incident scope ngay.

## 46. Forensics trong môi trường phù du

Pod/container có thể restart hoặc bị controller xóa nhanh. Chuẩn bị trước:

- audit/runtime/network log gửi ra ngoài node;
- mapping Pod UID ↔ container ID ↔ image digest ↔ node;
- process tree, command, capability, mount, namespace và connection metadata;
- snapshot volume/node theo quy định và tool đã kiểm chứng;
- synchronized timestamps và evidence hash/chain of custody;
- retention theo investigation window.

`kubectl exec` để điều tra có thể thay access time, process và filesystem. Dùng procedure/tool thu thập đã
test; không thu secret/plaintext quá mức cần thiết.

## 47. Multi-tenancy và hostile workload

Namespace multi-tenancy phù hợp khi tenant có mức tin cậy tương đối và cluster control chung được chấp nhận.
Với code khách hàng/untrusted, dùng sandbox RuntimeClass, node pool riêng, default-deny network, quota, không
token, không host access và egress proxy.

Hard multi-tenancy thường cần cluster riêng để tách API server, etcd, admission, CRD/operator và node. CRD
cluster-scoped hoặc operator quá quyền có thể phá isolation dù application RBAC trông đúng.

Đánh giá noisy neighbor, side channel, shared storage/cache/DNS và control-plane DoS, không chỉ pod-to-pod traffic.

## 48. Rollout và kiểm thử policy

Policy-as-code cần unit test và integration test trên version Kubernetes/CNI/runtime thực tế:

- manifest tốt được admit và chạy;
- privileged, hostPath, unconfined seccomp, mutable tag bị reject;
- default deny thật sự chặn traffic;
- token không được mount khi tắt;
- webhook outage hành xử đúng failure policy;
- policy không chặn system recovery ngoài thiết kế;
- exception hết hạn và bị alert;
- đường bypass node/CRI được phát hiện.

Triển khai audit/warn trước, canary namespace/cluster, quan sát latency/error rồi enforce. Version policy và
pin/test dependency của policy engine.

## 49. Metrics và SLO runtime security

| Metric | Điều cần đo |
|---|---|
| % workload đạt PSS restricted/baseline | coverage theo trust tier, không gộp exception |
| % Pod non-root/drop-all/seccomp/read-only | hardening thực tế trên container |
| % image chạy bằng verified digest | nối supply chain với runtime |
| % workload không cần và không mount SA token | giảm credential exposure |
| Namespace default-deny + tested allow coverage | enforcement dataplane |
| Privileged/host namespace/hostPath exception age | attack surface và debt |
| Audit/runtime sensor coverage + event loss | visibility thật |
| MTTD và contain/revoke latency | cửa sổ attacker hoạt động |
| Desired-observed digest/policy drift | bypass hoặc vận hành lệch |
| Node rebuild/compromise drill success | recoverability |

Tách metric theo production, tenant và criticality; tỷ lệ trung bình có thể che workload đặc biệt nguy hiểm.

## 50. Checklist production, anti-pattern và tài liệu chính thức

### Checklist tối thiểu

- [ ] Inventory workload, digest, ServiceAccount, secret, flow, volume, node pool và owner.
- [ ] PSS restricted cho app; exception nhỏ, có owner/expiry; admission policy được test.
- [ ] Non-root, `allowPrivilegeEscalation: false`, drop all capability, `RuntimeDefault` seccomp.
- [ ] Read-only root; writable volume giới hạn; không hostPath/runtime socket ngoài agent bắt buộc.
- [ ] Không privileged/host namespace; sandbox RuntimeClass cho code không tin cậy.
- [ ] ServiceAccount riêng, RBAC tối thiểu, projected token/audience; không mount token nếu không cần.
- [ ] Default-deny ingress/egress, allow flow đã test; chặn metadata và management endpoint.
- [ ] Request/limit/quota/PID phù hợp; node/runtime/kubelet được harden và patch.
- [ ] API audit + runtime telemetry gửi ra ngoài cluster, gắn với Pod UID và image digest.
- [ ] Runbook workload/node compromise được drill; revoke, quarantine và rebuild thay vì chỉ restart.

### Anti-pattern thường gặp

- “Container non-root nên không thể escape.”
- “Namespace là security boundary cứng.”
- “NetworkPolicy object tồn tại nghĩa traffic đã bị chặn.”
- “Privileged chỉ dùng tạm để debug.”
- “Không bind RBAC cho ServiceAccount nên token không có rủi ro.”
- “Admission policy bảo vệ được mọi process trên node.”
- “Xóa Pod là xử lý xong incident.”
- “Runtime alert càng nhiều thì detection càng tốt.”

### Tài liệu chính thức

- [Kubernetes – Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kubernetes – Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Kubernetes – Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Kubernetes – Linux kernel security constraints](https://kubernetes.io/docs/concepts/security/linux-kernel-security-constraints/)
- [Kubernetes – Seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Kubernetes – Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Kubernetes – Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes – RuntimeClass](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- [Kubernetes – Validating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [Kubernetes – API Server Bypass Risks](https://kubernetes.io/docs/concepts/security/api-server-bypass-risks/)
- [Kubernetes – Node Authorization](https://kubernetes.io/docs/reference/access-authn-authz/node/)
- [Kubernetes – Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Kubernetes – Security Checklist](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [Falco – Rules](https://falco.org/docs/concepts/rules/)
- [NIST SP 800-190 – Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final)

### Học tiếp

1. [Cloud-Native Detection & Incident Response](../detection/cloud_native_detection_incident_response.md) – correlation, triage, containment và forensic workflow.
2. [Platform Engineering Security](../platform/platform_engineering_security.md) – guardrail, golden path, policy ownership và multi-cluster governance.

---

*Cập nhật lần cuối: 2026-08-02.*
