#version 330 core
#include hg_sdf.glsl

#define PI 3.14159265
#define TAU (2*PI)
#define PHI (sqrt(5)*0.5 + 0.5)
#define saturate(x) clamp(x, 0, 1)

layout (location = 0) out vec4 fragColor;

uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;

const float FOV = 1.0; //область видимости камеры
const int MAX_STEPS = 256;
const float MAX_DIST = 500;
const float EPSILON = 0.001;

float fDisplace(vec3 p) {
    pR(p.yz, sin(2.0 * u_time));
    return (sin(p.x + 4.0 * u_time) * sin(p.y + sin(2.0 * u_time)) * sin(p.z + 6.0 * u_time));
}


//объединение пола и шарика
vec2 fOpUnionID(vec2 res1, vec2 res2){
    return (res1.x < res2.x) ? res1 : res2;
}


//функция для арок группа вычитания
vec2 fOpDifferenceID(vec2 res1, vec2 res2) {
    return (res1.x > -res2.x) ? res1 : vec2(-res2.x, res2.y);
}

//делаем переходик красивый
vec2 fOpDifferenceColumnsID(vec2 res1, vec2 res2, float r, float n) {
    float dist = fOpDifferenceColumns(res1.x, res2.x, r, n);
    return (res1.x > -res2.x) ? vec2(dist, res1.y) : vec2(dist, res2.y);
}

//функция для арок группа объединения
vec2 fOpUnionStairsID(vec2 res1, vec2 res2, float r, float n) {
    float dist = fOpUnionStairs(res1.x, res2.x, r, n);
    return (res1.x < res2.x) ? vec2(dist, res1.y) : vec2(dist, res2.y);
}

//делаем переходик красивый
vec2 fOpUnionChamferID(vec2 res1, vec2 res2, float r) {
    float dist = fOpUnionChamfer(res1.x, res2.x, r);
    return (res1.x < res2.x) ? vec2(dist, res1.y) : vec2(dist, res2.y);
}


//эта штука рендерит сцену
vec2 map(vec3 p){
    //пол
    float planeDist = fPlane(p, vec3(0, 1, 0), 10.0);
    float planeID = 2.0;
    vec2 plane = vec2(planeDist, planeID);

    //оператор бесконечного повторения объекта
    //p = mod(p, 4.0) - 4.0 * 0.5;
    //pMod3(p, vec3(5)); // из hg_sdf.glsl



    //сфера
    //float sphereDist = length(p) - 1.0; //SDF сферы

    float sphereDist = fSphere(p, 8.0 + fDisplace(p));
    float sphereID = 1.0; //tipo cvet
    vec2 sphere = vec2(sphereDist, sphereID);

    //модули смещения
    //отзеркалим по 2 осям
    pMirrorOctant(p.xz, vec2(50, 50));
    //повторение вдоль оси с шагом
    pMod1(p.z, 15);
    //модуль по оси с заданным смещением
    p.x = -abs(p.x) + 21;

    
    //крыша
    vec3 pr = p;
    pr.x -=36;
    pR(pr.xy, 0.6);
    pr.y -=32.0;
    float roofDist = fBox2(pr.xy, vec2(20, 0.3));
    float roofID = 4.0;
    vec2 roof = vec2(roofDist, roofID);

    //коробка
    float boxDist = fBox(p, vec3(3, 9, 4));
    float boxID = 3.0;
    vec2 box = vec2(boxDist, boxID);

    //цилиндр
    vec3 pc = p;
    pc.y -= 9.0;
    float cylinderDist = fCylinder(pc.yxz, 4, 3);
    float cylinderID = 3.0;
    vec2 cylinder = vec2(cylinderDist, cylinderID);

    //стена
    float wallDist = fBox2(p.xy, vec2(1, 15));
    float wallID = 3.0;
    vec2 wall = vec2(wallDist, wallID);


    //result 
    //vec2 res = sphere;
    vec2 res;
    //res = wall;
    res = fOpUnionID(box, cylinder);
    res = fOpDifferenceColumnsID(wall, res, 0.6, 3.0);
    res = fOpUnionChamferID(res, roof, 0.9);
    res = fOpUnionStairsID(res, plane, 4.0, 5.0);
    res = fOpUnionID(res, sphere);
    return res;
    //res = fOpUnionID(res, plane);
    
}


//эта хрень байбекает двумерный вектор object чтобы в Х расстояние а в У цвет
vec2 rayMarch(vec3 ro, vec3 rd){
    vec2 hit, object;
    for (int i = 0; i < MAX_STEPS; i++){
        vec3 p = ro + object.x *rd;
        hit = map(p);
        object.x += hit.x;
        object.y = hit.y;
        if(abs(hit.x) < EPSILON || object.x > MAX_DIST) break;
    }
    return object;
}

vec3 getNormal(vec3 p){
    //пикнем градиент через апроксимацию не оч догнал
    vec2 e = vec2(EPSILON, 0.0);
    vec3 n = vec3(map(p).x) - vec3(map(p - e.xyy).x, map(p - e.yxy).x, map(p - e.yyx).x);
    return normalize(n);
}

//освещение через Ламберта
vec3 getLight(vec3 p, vec3 rd, vec3 color){
    //кол-во отраженного света
    //пропорционально скалярному * вектора на
    //источник на нормаль к поверхности
    vec3 lightPos = vec3(10.0, 55.0, -20.0);
    vec3 L = normalize(lightPos - p);
    vec3 N = getNormal(p);
    //затенение по Фонгу
    vec3 V = -rd;
    vec3 R = reflect(-L, N);

    vec3 specColor = vec3(0.5);
    vec3 specular = specColor * pow(clamp(dot(R,V), 0.0, 1.0), 10.0);
    vec3 diffuse = color * clamp(dot(L,N), 0.0, 1.0);
    vec3 ambient = color * 0.05;
    vec3 fresnel = 0.25 * color * pow(1.0 + dot(rd, N), 3.0);

    //тени
    float d = rayMarch(p + N * 0.02, normalize(lightPos)).x;
    if (d < length(lightPos - p)) return ambient + fresnel;
    //if (d < length(lightPos - p)) return vec3(0);


    return diffuse + ambient + specular + fresnel;
    //return N;
}

vec3 getMaterial(vec3 p, float id){
    vec3 m;
    switch(int(id)){
        case 1:
        m = vec3(1.0, 0.0, 2.0); break;
        case 2:
        //m = vec3(0.0, 1.0, 2.0); break;
        m = vec3(0.2 + 0.4 * mod(floor(p.x) + floor(p.z), 2.0)); break;
        case 3:
        m = vec3(0.7, 0.8, 0.9); break;
        case 4:
        vec2 i = step(fract(0.5 * p.xz), vec2(1.0 / 10.0));
        m = ((1.0 - i.x) * (1.0 - i.y)) * vec3(0.37, 0.12, 0.0); break;
    }
    return m;
}

mat3 getCam(vec3 ro, vec3 lookAt){
    vec3 camF = normalize(vec3(lookAt - ro));
    vec3 camR = normalize(cross(vec3(0, 1, 0), camF));
    vec3 camU = cross(camF, camR);
    return mat3(camR, camU, camF);
}



void mouseControl(inout vec3 ro){
    vec2 m = u_mouse / u_resolution;
    pR(ro.yz, m.y * PI * 1 - 1);
    pR(ro.xz, m.x * TAU);
}


void render(inout vec3 col, in vec2 uv){
    vec3 ro = vec3(10.0, 10.0, 40.0);
    mouseControl(ro);
    vec3 lookAt = vec3(0, 0, 0);
    vec3 rd = getCam(ro, lookAt) * normalize(vec3(uv, FOV)); //по оси Z зырит

    vec2 object = rayMarch(ro, rd);

    //задний фон
    vec3 background = vec3(0.5, 0.8, 0.9);
    //если расстояние норм - вычисляем цвет
    if(object.x < MAX_DIST){
        vec3 p = ro + object.x *rd;
        vec3 material = getMaterial(p, object.y);
        col += getLight(p, rd, material);
        //туманчик сзади чтобы красивенько было
        col = mix(col, background, 1.0 - exp(-0.00002 * object.x * object.x));

        //col += getLight(p, rd, vec3(1));
        //col += 3.0 / object.x;
    } else{
        col += background - max(0.9 * rd.y, 0.0);
    }
}


void main() {
    //нормализаця систем координат чтобы 00 было по центру экрана
    vec2 uv = (2.0 * gl_FragCoord.xy - u_resolution.xy) / u_resolution.y;

    vec3 col;
    render(col, uv);

    //гамма коррекция
    col = pow(col, vec3(0.4545));
    
    fragColor = vec4(col, 1.0);
}